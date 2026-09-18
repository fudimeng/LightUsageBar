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
    static let expired = text("Access token expired: use Claude Code briefly to renew it, then refresh.",
                              "访问令牌已过期：打开 Claude Code 用一下即可自动续期，然后刷新")
    static let keychainPending = text("Keychain read timed out. If a Keychain prompt appears, choose Always Allow, then refresh.",
                                      "读取钥匙串超时：如出现钥匙串弹窗请点“始终允许”，然后刷新")
    static let keychainDenied = text("Keychain access was denied: allow LightUsageBar in the Keychain prompt, then refresh.",
                                     "钥匙串访问被拒绝：请在弹窗中允许 LightUsageBar 访问，然后刷新")
    static let timedOut = text("Timed out reading usage. It will retry on the next refresh.",
                               "读取额度超时，将在下次刷新时重试")
    static let signIn = text("Sign in to Claude Code first", "请先登录 Claude Code")
}
