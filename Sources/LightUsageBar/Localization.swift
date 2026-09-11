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
    static let expired = text("Login expired: open Claude Code or run /login, then refresh.",
                              "登录已过期：打开 Claude Code 或运行 /login，然后刷新")
    static let signIn = text("Sign in to Claude Code first", "请先登录 Claude Code")
}
