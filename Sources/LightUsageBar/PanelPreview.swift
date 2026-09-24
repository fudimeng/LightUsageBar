import AppKit

@MainActor
enum PanelPreview {
    static func render(to path: String) throws {
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 384, height: 432))
        canvas.appearance = NSAppearance(named: .aqua)
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor
        let reset = Date().addingTimeInterval(2 * 3600 + 13 * 60 + 30)
        for (index, name) in ["Claude", "Codex"].enumerated() {
            let data = ProviderUsage(provider: name,
                session: UsageWindow(usedPercent: index == 0 ? 28 : 54, resetsAt: reset, durationMinutes: 300),
                longWindow: UsageWindow(usedPercent: index == 0 ? 12 : 38,
                    resetsAt: reset.addingTimeInterval(5 * 86400), durationMinutes: 10080),
                plan: index == 0 ? "Max 5×" : "Pro")
            let panel = ProviderUsageView(name: name, result: .success(data))
            panel.frame.origin = NSPoint(x: 12, y: index == 0 ? 234 : 42)
            canvas.addSubview(panel)
        }
        let footer = NSTextField(labelWithString: "\(L10n.refresh)                         \(L10n.quit)")
        footer.frame = NSRect(x: 30, y: 13, width: 324, height: 20)
        footer.font = .systemFont(ofSize: 12)
        canvas.addSubview(footer)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.layoutSubtreeIfNeeded()
        guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
            throw UsageError.unavailable("Cannot allocate preview")
        }
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw UsageError.unavailable("Cannot encode preview")
        }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
