import Foundation

/// Turns the plan identifiers the providers report into plain plan names such as "Pro" or "Max",
/// without the finer grades the providers distinguish internally.
enum PlanName {
    /// Claude reports the plan in its stored login as subscriptionType, for example "max".
    static func claude(_ subscription: String?) -> String? {
        guard let subscription, !subscription.isEmpty else { return nil }
        switch subscription.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "free": return "Free"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return readable(subscription)
        }
    }

    /// Codex reports the plan as planType in its rate-limit snapshot, for example "prolite".
    static func codex(_ planType: String?) -> String? {
        guard let planType, !planType.isEmpty else { return nil }
        switch planType.lowercased() {
        // Pro Lite is graded below Pro; both read as Pro here.
        case "pro", "prolite": return "Pro"
        case "plus": return "Plus"
        case "free": return "Free"
        case "team", "business": return "Team"
        case "edu": return "Edu"
        case "enterprise": return "Enterprise"
        default: return readable(planType)
        }
    }

    /// Fallback for a plan this version does not know: "something_new" reads as "Something New".
    private static func readable(_ value: String) -> String {
        value.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.capitalized }.joined(separator: " ")
    }
}
