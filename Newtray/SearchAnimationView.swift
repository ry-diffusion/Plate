//
//  SearchAnimationView.swift
//  Newtray
//
//  The iPhone's "searching for network" animation, drawn over the menu bar
//  item's static no-service glyph. Core Animation runs it in the render server,
//  so the app doesn't redraw anything while it plays.
//

import AppKit

final class SearchAnimationView: NSView {
    /// One mark per bar or dot: its resting frame and the frame it grows to as
    /// the wave passes (the same frame for dots, which only brighten).
    struct Mark {
        let rest: NSRect
        let peak: NSRect
    }

    private static let samples = 60

    init(frame: NSRect, marks: [Mark], color: NSColor, cycle: TimeInterval) {
        super.init(frame: frame)
        wantsLayer = true
        guard let root = layer else { return }
        let start = CACurrentMediaTime()

        for (index, mark) in marks.enumerated() {
            let shape = CALayer()
            shape.backgroundColor = color.cgColor
            shape.cornerRadius = min(mark.rest.width, mark.rest.height) / 2
            // Grows upward from its bottom edge.
            shape.anchorPoint = CGPoint(x: 0.5, y: 0)
            shape.position = CGPoint(x: mark.rest.midX, y: mark.rest.minY)
            shape.bounds = CGRect(origin: .zero, size: mark.rest.size)
            shape.opacity = 0
            root.addSublayer(shape)

            // Samples the same wave the static glyphs use.
            let phases = (0...Self.samples).map { CGFloat($0) / CGFloat(Self.samples) }
            let glows = phases.map { HotspotDevice.searchGlow(index: index, phase: $0) }

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = glows.map { Float($0) }

            let bounds = CAKeyframeAnimation(keyPath: "bounds")
            bounds.values = glows.map { glow in
                let height = mark.rest.height + glow * (mark.peak.height - mark.rest.height)
                return NSValue(rect: NSRect(x: 0, y: 0, width: mark.rest.width, height: height))
            }

            let group = CAAnimationGroup()
            group.animations = [opacity, bounds]
            group.duration = cycle
            group.repeatCount = .infinity
            group.beginTime = start
            group.isRemovedOnCompletion = false
            shape.add(group, forKey: "search")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Clicks go through to the status item's button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
