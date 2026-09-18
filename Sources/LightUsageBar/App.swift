import AppKit
import Foundation

struct UsageWindow: Sendable {
    let usedPercent: Int
    let resetsAt: Date?
    let durationMinutes: Int?

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
}

struct ProviderUsage: Sendable {
    let provider: String
    let session: UsageWindow?
    let longWindow: UsageWindow?
    let detail: String?
}

enum UsageError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let refreshInterval: TimeInterval = 5 * 60
    private var refreshTimer: Timer?
    private var latest: [String: Result<ProviderUsage, Error>] = [:]
    private var inFlight: Set<String> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateStatusText()
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        rebuildMenu()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { refreshTimer?.invalidate() }

    @objc private func refresh() {
        load("Claude", timeout: 90) { try await ClaudeUsageFetcher.fetch() }
        load("Codex", timeout: 20) { try await CodexUsageFetcher.fetch() }
    }

    /// Loads one provider independently so a slow or stuck provider never delays the other.
    /// A timeout shows an error in the panel; a late result still replaces it when it arrives.
    private func load(_ name: String, timeout: TimeInterval,
                      _ fetch: @escaping @Sendable () async throws -> ProviderUsage) {
        guard !inFlight.contains(name) else { return }
        inFlight.insert(name)
        let work = Task.detached(priority: .utility) { try await fetch() }
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self else { return }
            self.apply(name, .failure(UsageError.unavailable(L10n.timedOut)))
        }
        Task { [weak self] in
            let result: Result<ProviderUsage, Error>
            do { result = .success(try await work.value) } catch { result = .failure(error) }
            watchdog.cancel()
            guard let self else { return }
            self.inFlight.remove(name)
            self.apply(name, result)
        }
    }

    private func apply(_ name: String, _ result: Result<ProviderUsage, Error>) {
        latest[name] = result
        updateStatusText()
        rebuildMenu()
    }

    private func updateStatusText() {
        let providers = ["Claude", "Codex"]
        let values = providers.map { name -> (String, String) in
            guard case .success(let usage)? = latest[name] else { return ("—", "—") }
            let windows = [usage.session, usage.longWindow].compactMap { $0 }
            let short = windows.first { $0.durationMinutes == 300 }
            let weekly = windows.first { $0.durationMinutes == 10_080 }
            return (short.map { "\($0.remainingPercent)%" } ?? "—",
                    weekly.map { "\($0.remainingPercent)%" } ?? "—")
        }
        // Template artwork inherits the menu bar's light/dark and selected colors.
        // A 20-point canvas keeps both lines inside the standard menu bar height.
        let image = NSImage(size: NSSize(width: 104, height: 20))
        image.lockFocus()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let numbers: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph
        ]
        for index in providers.indices {
            let x = CGFloat(index * 54)
            let label = index == 0 ? "C" : "X"
            (label as NSString).draw(at: NSPoint(x: x, y: 3.5), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.black
            ])
            (values[index].0 as NSString).draw(in: NSRect(x: x + 11, y: 10, width: 36, height: 10), withAttributes: numbers)
            (values[index].1 as NSString).draw(in: NSRect(x: x + 11, y: 0, width: 36, height: 10), withAttributes: numbers)
        }
        image.unlockFocus()
        image.isTemplate = true
        statusItem.button?.title = ""
        statusItem.button?.image = image
        let description = providers.indices.map {
            "\(providers[$0]): \(L10n.short) \(values[$0].0), \(L10n.weekly) \(values[$0].1)"
        }.joined(separator: "\n")
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for name in ["Claude", "Codex"] {
            let item = NSMenuItem()
            item.view = ProviderUsageView(name: name, result: latest[name])
            item.isEnabled = true
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: L10n.refresh, action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = true
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func text(for name: String) -> String {
        guard let result = latest[name] else { return "\(name): loading…" }
        switch result {
        case .success(let usage):
            var parts: [String] = []
            if let session = usage.session { parts.append("\(label(session)) \(session.remainingPercent)% · \(resetText(session))") }
            if let long = usage.longWindow { parts.append("\(label(long)) \(long.remainingPercent)% · \(resetText(long))") }
            return "\(name): " + (parts.isEmpty ? "no limit returned" : parts.joined(separator: "    "))
        case .failure(let error):
            return "\(name): \(error.localizedDescription)"
        }
    }

    private func resetText(_ window: UsageWindow) -> String {
        guard let reset = window.resetsAt else { return "reset time unavailable" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "resets \(formatter.localizedString(for: reset, relativeTo: Date()))"
    }

    private func label(_ window: UsageWindow) -> String {
        switch window.durationMinutes {
        case 300: return "5h"
        case 10080: return "week"
        case let minutes? where minutes < 1440: return "\(minutes)m"
        case let minutes?: return "\(minutes / 1440)d"
        case nil: return "limit"
        }
    }
}

@main
struct LightUsageBarMain {
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render-preview" {
            do { try PanelPreview.render(to: CommandLine.arguments[2]) }
            catch { fputs("Preview rendering failed\n", stderr); exit(1) }
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

enum CodexUsageFetcher {
    static func fetch() async throws -> ProviderUsage {
        try await Task.detached(priority: .utility) {
            let response = try AppServerClient.requestRateLimits()
            let result = response["result"] as? [String: Any] ?? [:]
            let snapshot = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
                ?? result["rateLimits"] as? [String: Any] ?? [:]
            return ProviderUsage(provider: "Codex", session: window(snapshot["primary"]), longWindow: window(snapshot["secondary"]), detail: nil)
        }.value
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let json = value as? [String: Any], let used = json["usedPercent"] as? Int else { return nil }
        let epoch = json["resetsAt"] as? TimeInterval
        return UsageWindow(usedPercent: used, resetsAt: epoch.map { Date(timeIntervalSince1970: $0) }, durationMinutes: json["windowDurationMins"] as? Int)
    }
}

enum ClaudeUsageFetcher {
    static func fetch() async throws -> ProviderUsage {
        let token = try await Task.detached(priority: .utility) { try ClaudeCredentials.token() }.value
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("LightUsageBar/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.unavailable(L10n.text("Invalid server response", "无法读取服务器响应"))
        }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw UsageError.unavailable(L10n.expired)
        case 403: throw UsageError.unavailable(L10n.text("Access denied (403): sign in to Claude Code again.", "无权读取用量 (403)：请在 Claude Code 中重新登录"))
        case 429: throw UsageError.unavailable(L10n.text("Too many requests (429): try again later.", "请求过于频繁 (429)：请稍后刷新"))
        default: throw UsageError.unavailable("\(L10n.text("Usage request failed", "用量请求失败")) (HTTP \(http.statusCode))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.unavailable(L10n.text("Unrecognized usage response", "无法识别用量响应"))
        }
        return ProviderUsage(provider: "Claude", session: window(json["five_hour"], duration: 300), longWindow: window(json["seven_day"], duration: 10_080), detail: nil)
    }

    private static func window(_ value: Any?, duration: Int) -> UsageWindow? {
        guard let json = value as? [String: Any], let used = json["utilization"] as? Double else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let reset = (json["resets_at"] as? String).flatMap {
            formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
        }
        return UsageWindow(usedPercent: Int(used.rounded()), resetsAt: reset, durationMinutes: duration)
    }
}

enum ClaudeCredentials {
    static func token() throws -> String {
        let value: String
        switch ProcessRunner.run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 60) {
        case .success(let output): value = output
        case .timedOut: throw UsageError.unavailable(L10n.keychainPending)
        // errSecItemNotFound: Claude Code has never stored a login on this Mac.
        case .failed(let status) where status == 44: throw UsageError.unavailable(L10n.signIn)
        case .failed: throw UsageError.unavailable(L10n.keychainDenied)
        case .launchFailed: throw UsageError.unavailable(L10n.keychainDenied)
        }
        guard let data = value.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (json["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String else {
            throw UsageError.unavailable(L10n.signIn)
        }
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let expiry = oauth["expiresAt"] as? Double,
           expiry / 1000 <= Date().timeIntervalSince1970 {
            throw UsageError.unavailable(L10n.expired)
        }
        return token
    }
}

enum AppServerClient {
    static func requestRateLimits() throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--stdio"]
        // Finder-launched apps often do not inherit Homebrew's PATH.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        // availableData blocks until output arrives, so the deadline must end the process itself.
        let watchdog = ProcessWatchdog(process, after: 12)
        defer { watchdog.cancel(); if process.isRunning { process.terminate() } }

        let initialize: [String: Any] = ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "LightUsageBar", "version": "0.1"]]]
        let initialized: [String: Any] = ["method": "initialized"]
        let read: [String: Any] = ["id": 2, "method": "account/rateLimits/read", "params": NSNull()]
        for request in [initialize, initialized, read] {
            let data = try JSONSerialization.data(withJSONObject: request)
            input.fileHandleForWriting.write(data + Data([0x0A]))
        }

        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            for line in buffer.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      (object["id"] as? Int) == 2 else { continue }
                return object
            }
        }
        throw UsageError.unavailable(L10n.text("Codex CLI did not return rate limits", "Codex CLI 未返回额度"))
    }
}

enum ProcessRunner {
    enum Outcome {
        case success(String)
        case failed(Int32)
        case timedOut
        case launchFailed
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .launchFailed }
        let watchdog = ProcessWatchdog(process, after: timeout)
        // Drain stdout before waiting: Claude credentials can exceed the 64 KB pipe buffer,
        // and waiting first deadlocks with the child blocked on write.
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        if watchdog.fired { return .timedOut }
        guard process.terminationStatus == 0 else { return .failed(process.terminationStatus) }
        return .success(String(decoding: output, as: UTF8.self))
    }
}

/// Terminates a child process if it is still running after a deadline.
final class ProcessWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var didFire = false
    private var item: DispatchWorkItem?

    /// True when the deadline passed and the process was terminated by this watchdog.
    var fired: Bool { lock.withLock { didFire } }

    init(_ process: Process, after seconds: TimeInterval) {
        let target = process
        let item = DispatchWorkItem { [weak self] in
            guard target.isRunning else { return }
            self?.lock.withLock { self?.didFire = true }
            target.terminate()
        }
        self.item = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func cancel() { item?.cancel() }
}
