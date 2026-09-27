import AppKit
import Foundation

enum UsageProvider: String, CaseIterable {
    case claude = "Claude"
    case codex = "Codex"

    var loginCommand: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex login"
        }
    }

    var authenticationDescription: String {
        switch self {
        case .claude: L10n.text("Uses the existing Claude Code login in macOS Keychain. Run claude, then /login if needed.",
                                "使用 macOS 钥匙串中已有的 Claude Code 登录。需要登录时运行 claude，再输入 /login。")
        case .codex: L10n.text("Uses the existing Codex CLI login through codex app-server. Run codex login if needed.",
                               "通过 codex app-server 使用已有的 Codex CLI 登录。需要登录时运行 codex login。")
        }
    }
}

@MainActor
final class ProviderSettings {
    static let shared = ProviderSettings()
    private let key = "enabledProviders"
    private(set) var enabled: Set<UsageProvider>

    private init() {
        let names = UserDefaults.standard.stringArray(forKey: key) ?? []
        enabled = Set(names.compactMap(UsageProvider.init(rawValue:)))
    }

    var hasSavedSelection: Bool { UserDefaults.standard.object(forKey: key) != nil }

    func set(_ provider: UsageProvider, enabled isEnabled: Bool) {
        if isEnabled { enabled.insert(provider) } else { enabled.remove(provider) }
        UserDefaults.standard.set(UsageProvider.allCases.filter { enabled.contains($0) }.map(\.rawValue), forKey: key)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var switches: [UsageProvider: NSButton] = [:]
    private var statuses: [UsageProvider: NSTextField] = [:]
    var onChange: ((UsageProvider, Bool) -> Void)?
    var onRefresh: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 350),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = L10n.settings
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateStatus(_ provider: UsageProvider, result: Result<ProviderUsage, Error>?) {
        guard let field = statuses[provider] else { return }
        if !ProviderSettings.shared.enabled.contains(provider) {
            field.stringValue = L10n.notEnabled
            field.textColor = .secondaryLabelColor
        } else if let result {
            switch result {
            case .success: field.stringValue = L10n.connected; field.textColor = .systemGreen
            case .failure(let error): field.stringValue = error.localizedDescription; field.textColor = .systemOrange
            }
        } else {
            field.stringValue = L10n.loading
            field.textColor = .secondaryLabelColor
        }
        field.toolTip = field.stringValue
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: L10n.providersTitle)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 24, y: 306, width: 462, height: 27)
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: L10n.providersSubtitle)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 282, width: 462, height: 20)
        content.addSubview(subtitle)

        for (index, provider) in UsageProvider.allCases.enumerated() {
            let top = CGFloat(269 - index * 112)
            let card = NSBox(frame: NSRect(x: 24, y: top - 104, width: 462, height: 100))
            card.boxType = .custom
            card.borderColor = .separatorColor
            card.cornerRadius = 9
            content.addSubview(card)

            let toggle = NSButton(checkboxWithTitle: provider.rawValue, target: self, action: #selector(toggleProvider(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
            toggle.state = ProviderSettings.shared.enabled.contains(provider) ? .on : .off
            toggle.font = .systemFont(ofSize: 14, weight: .semibold)
            toggle.frame = NSRect(x: 14, y: 69, width: 240, height: 22)
            card.addSubview(toggle)
            switches[provider] = toggle

            let copy = NSButton(title: L10n.copyLoginCommand, target: self, action: #selector(copyCommand(_:)))
            copy.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
            copy.bezelStyle = .rounded
            copy.frame = NSRect(x: 322, y: 66, width: 126, height: 28)
            card.addSubview(copy)

            let description = NSTextField(wrappingLabelWithString: provider.authenticationDescription)
            description.font = .systemFont(ofSize: 11)
            description.textColor = .secondaryLabelColor
            description.frame = NSRect(x: 14, y: 33, width: 432, height: 31)
            card.addSubview(description)

            let status = NSTextField(labelWithString: L10n.notEnabled)
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            status.lineBreakMode = .byTruncatingTail
            status.frame = NSRect(x: 14, y: 9, width: 432, height: 19)
            card.addSubview(status)
            statuses[provider] = status
        }

        let refresh = NSButton(title: L10n.refresh, target: self, action: #selector(refreshSelected))
        refresh.bezelStyle = .rounded
        refresh.frame = NSRect(x: 354, y: 12, width: 132, height: 28)
        content.addSubview(refresh)
    }

    @objc private func toggleProvider(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let provider = UsageProvider(rawValue: rawValue) else { return }
        let isEnabled = sender.state == .on
        ProviderSettings.shared.set(provider, enabled: isEnabled)
        updateStatus(provider, result: nil)
        onChange?(provider, isEnabled)
    }

    @objc private func copyCommand(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let provider = UsageProvider(rawValue: rawValue) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(provider.loginCommand, forType: .string)
    }

    @objc private func refreshSelected() { onRefresh?() }
}
