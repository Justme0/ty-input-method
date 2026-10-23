import Cocoa

final class CandidatePanel {
    static let shared = CandidatePanel()

    var onPick: ((Int) -> Void)?

    private let panel: NSPanel
    private let view = CandidateView()

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        view.onPick = { [weak self] index in
            self?.onPick?(index)
        }
        panel.contentView = view
    }

    func show(candidates: [String], highlight: Int, page: Int, pageCount: Int, caret: NSRect) {
        guard !candidates.isEmpty else {
            hide()
            return
        }
        view.items = candidates
        view.highlight = highlight
        view.pageText = pageCount > 1 ? "\(page + 1)/\(pageCount)" : ""
        view.relayout()
        let size = view.bounds.size
        var frame = NSRect(origin: .zero, size: size)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret) || $0.frame.contains(caret.origin) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var caretRect = caret
        if caretRect.width == 0 && caretRect.height == 0 {
            caretRect = NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 1, height: 18))
        }
        frame.origin.x = caretRect.minX
        frame.origin.y = caretRect.minY - size.height - 4
        if frame.maxX > visible.maxX - 8 {
            frame.origin.x = visible.maxX - size.width - 8
        }
        if frame.minX < visible.minX + 8 {
            frame.origin.x = visible.minX + 8
        }
        if frame.minY < visible.minY + 4 {
            frame.origin.y = caretRect.maxY + 4
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var visibleCandidates: [String] { view.items }

    func snapshotPNG() -> Data? {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

final class CandidateView: NSView {
    var items: [String] = []
    var highlight = 0
    var pageText = ""
    var onPick: ((Int) -> Void)?

    private var frames: [NSRect] = []
    private let font = NSFont.systemFont(ofSize: 16)
    private let indexFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    override var isFlipped: Bool { true }

    func relayout() {
        frames = []
        var x: CGFloat = 8
        for (index, text) in items.enumerated() {
            let label = "\(index + 1) \(text)" as NSString
            let width = label.size(withAttributes: [.font: font]).width + 18
            frames.append(NSRect(x: x, y: 4, width: width, height: 28))
            x += width + 4
        }
        var width = max(80, x + 8)
        if !pageText.isEmpty {
            width += 44
        }
        setFrameSize(NSSize(width: width, height: 36))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.setFill()
        background.fill()
        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()

        for (index, text) in items.enumerated() {
            guard index < frames.count else { continue }
            let frame = frames[index]
            if index == highlight {
                let pill = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
                NSColor.selectedContentBackgroundColor.setFill()
                pill.fill()
            }
            let number = "\(index + 1)" as NSString
            let body = text as NSString
            let numberColor = index == highlight ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85) : NSColor.secondaryLabelColor
            let bodyColor = index == highlight ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor
            let numberSize = number.size(withAttributes: [.font: indexFont])
            number.draw(
                at: NSPoint(x: frame.minX + 8, y: frame.midY - numberSize.height / 2),
                withAttributes: [.font: indexFont, .foregroundColor: numberColor]
            )
            let bodySize = body.size(withAttributes: [.font: font])
            body.draw(
                at: NSPoint(x: frame.minX + 8 + numberSize.width + 4, y: frame.midY - bodySize.height / 2),
                withAttributes: [.font: font, .foregroundColor: bodyColor]
            )
        }

        if !pageText.isEmpty {
            let label = pageText as NSString
            let size = label.size(withAttributes: [.font: indexFont])
            label.draw(
                at: NSPoint(x: bounds.maxX - size.width - 10, y: bounds.midY - size.height / 2),
                withAttributes: [.font: indexFont, .foregroundColor: NSColor.secondaryLabelColor]
            )
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, frame) in frames.enumerated() where frame.contains(point) {
            onPick?(index)
            return
        }
    }
}
