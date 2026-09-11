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
        statusItem.button?.toolTip = "正在刷新剩余额度…"
        Task { [weak self] in
            async let codex = CodexUsageFetcher.fetch()
            async let claude = ClaudeUsageFetcher.fetch()
            let codexResult: Result<ProviderUsage, Error>
            let claudeResult: Result<ProviderUsage, Error>
            do { codexResult = .success(try await codex) } catch { codexResult = .failure(error) }
            do { claudeResult = .success(try await claude) } catch { claudeResult = .failure(error) }
            guard let self else { return }
            self.latest = ["Codex": codexResult, "Claude": claudeResult]
            self.updateStatusText()
            self.rebuildMenu()
        }
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
            "\(providers[$0])：5 小时剩余 \(values[$0].0)，周剩余 \(values[$0].1)"
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
        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = true
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "Quit LightUsageBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            throw UsageError.unavailable("无法读取服务器响应")
        }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw UsageError.unavailable("登录已失效：在 Claude Code 中运行 /login，然后刷新")
        case 403: throw UsageError.unavailable("无权读取用量 (403)：请在 Claude Code 中重新登录")
        case 429: throw UsageError.unavailable("请求过于频繁 (429)：请稍后刷新")
        default: throw UsageError.unavailable("用量请求失败 (HTTP \(http.statusCode))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.unavailable("unrecognized usage response")
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
        let value = try ProcessRunner.run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        guard let data = value.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (json["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String else {
            throw UsageError.unavailable("sign in to Claude Code first")
        }
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let expiry = oauth["expiresAt"] as? Double,
           expiry / 1000 <= Date().timeIntervalSince1970 {
            throw UsageError.unavailable("登录已过期：打开 Claude Code；若仍失败，运行 /login")
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
        defer { if process.isRunning { process.terminate() } }

        let initialize: [String: Any] = ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "LightUsageBar", "version": "0.1"]]]
        let initialized: [String: Any] = ["method": "initialized"]
        let read: [String: Any] = ["id": 2, "method": "account/rateLimits/read", "params": NSNull()]
        for request in [initialize, initialized, read] {
            let data = try JSONSerialization.data(withJSONObject: request)
            input.fileHandleForWriting.write(data + Data([0x0A]))
        }

        var buffer = Data()
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            for line in buffer.split(separator: 0x0A) {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      (object["id"] as? Int) == 2 else { continue }
                return object
            }
        }
        throw UsageError.unavailable("Codex CLI did not return rate limits")
    }
}

enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UsageError.unavailable("sign in to Claude Code first") }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
