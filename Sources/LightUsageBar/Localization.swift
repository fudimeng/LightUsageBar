import Foundation

enum L10n {
    static var isChinese: Bool {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    }

    static func text(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }

    static let short = text("5-hour remaining", "5 小时剩余额度")
    static let weekly = text("Weekly remaining", "周剩余额度")
    static let missing = text("Not provided", "未提供该额度")
    static let loading = text("Loading usage…", "正在读取额度…")
    static let refresh = text("Refresh now", "立即刷新")
    static let quit = text("Quit LightUsageBar", "退出 LightUsageBar")
    static let expired = text("Claude rejected the renewed token: run claude in Terminal and use /login, then refresh.",
                              "Claude 拒绝了续期后的令牌：请在终端运行 claude 并执行 /login，然后刷新")
    static let loginInvalid = text("Claude login is no longer valid: run claude in Terminal and use /login, then refresh.",
                                   "Claude 登录已失效：请在终端运行 claude 并执行 /login，然后刷新")
    static let renewFailed = text("Could not renew the Claude access token. It will retry on the next refresh.",
                                  "续期 Claude 访问令牌失败，将在下次刷新时重试")
    static let renewBusy = text("Claude Code is renewing the token right now. It will retry on the next refresh.",
                                "Claude Code 正在续期令牌，将在下次刷新时重试")
    static let writeBackFailed = text("Renewed the token but could not save it to the Keychain. It will retry on the next refresh.",
                                      "令牌已续期，但写回钥匙串失败，将在下次刷新时重试")
    static let keychainPending = text("Keychain read timed out. If a Keychain prompt appears, choose Always Allow, then refresh.",
                                      "读取钥匙串超时：如出现钥匙串弹窗请点“始终允许”，然后刷新")
    static let keychainDenied = text("Keychain access was denied: allow LightUsageBar in the Keychain prompt, then refresh.",
                                     "钥匙串访问被拒绝：请在弹窗中允许 LightUsageBar 访问，然后刷新")
    static let timedOut = text("Timed out reading usage. It will retry on the next refresh.",
                               "读取额度超时，将在下次刷新时重试")
    static let signIn = text("Sign in to Claude Code first", "请先登录 Claude Code")
}
