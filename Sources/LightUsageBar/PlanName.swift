import Foundation

/// Turns the plan identifiers the providers report into the names they use publicly.
enum PlanName {
    /// Claude reports the plan in its stored login: "max" plus a rate-limit tier
    /// such as "default_claude_max_5x", which is the 5× Max plan.
    static func claude(subscription: String?, tier: String?) -> String? {
        guard let subscription, !subscription.isEmpty else { return nil }
        let multiplier = tier.flatMap { value -> String? in
            guard let match = value.range(of: #"(\d+)x"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
            return String(value[match]).lowercased().replacingOccurrences(of: "x", with: "×")
        }
        switch subscription.lowercased() {
        case "max": return multiplier.map { "Max \($0)" } ?? "Max"
        case "pro": return "Pro"
        case "team", "enterprise": return subscription.capitalized
        case "free": return "Free"
        default: return readable(subscription)
        }
    }

    /// Codex reports the plan as planType in its rate-limit snapshot, for example "prolite".
    static func codex(_ planType: String?) -> String? {
        guard let planType, !planType.isEmpty else { return nil }
        switch planType.lowercased() {
        case "prolite": return "Pro Lite"
        case "pro": return "Pro"
        case "plus": return "Plus"
        case "team", "business": return "Team"
        case "edu": return "Edu"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return readable(planType)
        }
    }

    /// Fallback for a plan this version does not know: "something_new" reads as "Something New".
    private static func readable(_ value: String) -> String {
        value.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.capitalized }.joined(separator: " ")
    }
}
