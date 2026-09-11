import AppKit

/// Fixed-height informational menu content; the system menu retains keyboard navigation.
@MainActor
final class ProviderUsageView: NSView {
    override var isFlipped: Bool { true }

    init(name: String, result: Result<ProviderUsage, Error>?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 186))
        label(name, frame: NSRect(x: 18, y: 9, width: 324, height: 22), size: 14, weight: .semibold)
        let usage: ProviderUsage?
        let unavailable: String
        switch result {
        case .success(let value): usage = value; unavailable = L10n.missing
        case .failure(let error): usage = nil; unavailable = error.localizedDescription
        case nil: usage = nil; unavailable = L10n.loading
        }
        let windows = [usage?.session, usage?.longWindow].compactMap { $0 }
        row(title: L10n.short, window: windows.first { $0.durationMinutes == 300 },
            y: 38, unavailable: unavailable)
        row(title: L10n.weekly, window: windows.first { $0.durationMinutes == 10_080 },
            y: 109, unavailable: unavailable)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func row(title: String, window: UsageWindow?, y: CGFloat, unavailable: String) {
        label(title, frame: NSRect(x: 18, y: y, width: 248, height: 18), size: 12)
        let number = label(window.map { "\($0.remainingPercent)%" } ?? "—",
                           frame: NSRect(x: 274, y: y, width: 68, height: 18), size: 12, weight: .semibold)
        number.alignment = .right
        number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let bar = RemainingBar(frame: NSRect(x: 18, y: y + 24, width: 324, height: 7))
        bar.remaining = window?.remainingPercent
        bar.setAccessibilityElement(true)
        bar.setAccessibilityRole(.progressIndicator)
        bar.setAccessibilityLabel(title)
        bar.setAccessibilityValue(window.map { "\($0.remainingPercent)%" } ?? L10n.missing)
        addSubview(bar)
        let reset = window.map { Self.resetText($0.resetsAt) } ?? unavailable
        let caption = label(reset, frame: NSRect(x: 18, y: y + 37, width: 324, height: 29), size: 11)
        caption.maximumNumberOfLines = 2
        caption.lineBreakMode = .byWordWrapping
        caption.toolTip = reset
    }

    @discardableResult
    private func label(_ text: String, frame: NSRect, size: CGFloat,
                       weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = .labelColor
        addSubview(field)
        return field
    }

    static func resetText(_ date: Date?) -> String {
        guard let date else { return L10n.text("Reset time unavailable", "重置时间未提供") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isChinese ? "zh_CN" : "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = L10n.isChinese ? "MM月dd日 HH:mm" : "MMM d, HH:mm"
        let offsetMinutes = formatter.timeZone.secondsFromGMT(for: date) / 60
        let sign = offsetMinutes < 0 ? "−" : "+"
        let hours = abs(offsetMinutes) / 60
        let minutes = abs(offsetMinutes) % 60
        let suffix = minutes == 0 ? "" : String(format: ":%02d", minutes)
        let zone = offsetMinutes == 0 ? "UTC" : "UTC\(sign)\(hours)\(suffix)"
        return "\(L10n.text("Resets", "重置于")) \(formatter.string(from: date)) \(zone)"
    }
}

@MainActor
private final class RemainingBar: NSView {
    var remaining: Int?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3.5, yRadius: 3.5).fill()
        guard let remaining, remaining > 0 else { return }
        let color: NSColor = remaining <= 10 ? .systemRed : remaining <= 25 ? .systemOrange : .systemBlue
        color.setFill()
        let fill = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(remaining) / 100, height: bounds.height)
        NSBezierPath(roundedRect: fill, xRadius: min(3.5, fill.width / 2), yRadius: 3.5).fill()
    }
}
