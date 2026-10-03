//
//  MenuRowHostView.swift
//  Plate
//
//  Hosts a SwiftUI row inside an NSMenuItem with the menu's own highlight:
//  NSMenu tracks which item is highlighted (mouse and keyboard), and this view
//  draws it. SwiftUI's onHover doesn't work for this, since the menu never
//  reports the pointer leaving a row while it tracks.
//

import AppKit
import SwiftUI

final class MenuRowHostView<Content: View>: NSView {
    private let onSelect: (() -> Void)?

    init(rootView: Content, onSelect: (() -> Void)?) {
        self.onSelect = onSelect
        let host = NSHostingView(rootView: rootView)
        super.init(frame: NSRect(origin: .zero, size: host.fittingSize))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard onSelect != nil, enclosingMenuItem?.isHighlighted == true else { return }
        // A rounded selection inset from the menu's edges, like system rows.
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 6, yRadius: 6).fill()
    }

    override func mouseUp(with event: NSEvent) {
        guard let onSelect, let item = enclosingMenuItem else { return }
        // Closes the whole menu (submenus included) before acting.
        var menu = item.menu
        while let parent = menu?.supermenu { menu = parent }
        menu?.cancelTracking()
        onSelect()
    }

    /// Lets Return pick the highlighted row too.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.keyCode == 36, enclosingMenuItem?.isHighlighted == true, onSelect != nil else {
            return super.performKeyEquivalent(with: event)
        }
        mouseUp(with: event)
        return true
    }
}
