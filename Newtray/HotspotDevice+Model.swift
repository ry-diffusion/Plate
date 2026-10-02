//
//  HotspotDevice+Model.swift
//  Newtray
//
//  Marketing name and icon for the device from its model identifier
//  ("iPhone18,1" → "iPhone 17 Pro"), using the UTIs that macOS CoreTypes
//  registers for each model.
//

import AppKit
import UniformTypeIdentifiers

extension HotspotDevice {
    private var modelType: UTType? {
        guard !model.isEmpty,
              let type = UTType(tag: model, tagClass: UTTagClass(rawValue: "com.apple.device-model-code"), conformingTo: nil),
              !type.isDynamic else { return nil }
        return type
    }

    /// "iPhone 17 Pro"; falls back to the raw identifier if macOS doesn't know the model.
    var modelName: String {
        modelType?.localizedDescription ?? model
    }

    var modelIcon: NSImage {
        if let modelType {
            return NSWorkspace.shared.icon(for: modelType)
        }
        return NSImage(systemSymbolName: "iphone", accessibilityDescription: nil) ?? NSImage()
    }

    /// The iPhone advertises its battery in quarters (0, 25, 50, 75, 100), so it's
    /// shown as a 0–4 level, never as a percentage.
    var batteryQuarters: Int {
        min(max(Int((Double(batteryLevel) / 25).rounded()), 0), 4)
    }

    /// Signal bars with, optionally, the iPhone battery as a row of 4 marks below
    /// (one under each bar), filled left to right by quarter: a full quarter is
    /// a segment as wide as its bar, an empty one is a small faint dot. No
    /// percentage: the iPhone only advertises its battery in quarters.
    ///
    /// With `canvasHeight` (the menu bar button height), the bars always stay
    /// centered, with or without the battery, and the dots use the space left
    /// below. `verticalOffset` raises the bars (in points) to match the optical
    /// center of the other items. Without `canvasHeight`, the image is tight
    /// (for use in the menu).
    /// Template image: the menu bar does the tinting.
    func signalGlyph(pointSize: CGFloat, showBattery: Bool, trailingPadding: CGFloat = 0,
                     canvasHeight: CGFloat? = nil, verticalOffset: CGFloat = 0) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let bars = NSImage(systemSymbolName: "cellularbars", variableValue: Double(signalBars) / 4,
                                 accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }

        // At 15pt: 2pt-tall segments, 1pt below the bars. The menu bar button
        // clips ~1.5pt off the bottom of the image, so they can't be any taller.
        let segmentHeight = (pointSize * 0.135).rounded()
        let emptyDot = segmentHeight * 0.7
        let spacing = (pointSize / 15).rounded()
        let compactHeight = bars.size.height + (showBattery ? segmentHeight + spacing : 0)
        let height = max(canvasHeight ?? compactHeight, compactHeight)
        let barsY = canvasHeight == nil
            ? height - bars.size.height
            : ((height - bars.size.height) / 2).rounded() + verticalOffset
        let segmentsY = barsY - spacing - segmentHeight
        let filled = batteryQuarters
        let spans = Self.barSpans(pointSize: pointSize)

        let image = NSImage(size: NSSize(width: bars.size.width + trailingPadding, height: height), flipped: false) { _ in
            bars.draw(in: NSRect(x: 0, y: barsY, width: bars.size.width, height: bars.size.height))
            guard showBattery else { return true }
            for (index, span) in spans.enumerated() {
                let mark: NSRect
                if index < filled {
                    NSColor.black.setFill()
                    mark = NSRect(x: span.lowerBound, y: segmentsY, width: span.upperBound - span.lowerBound, height: segmentHeight)
                } else {
                    NSColor.black.withAlphaComponent(0.35).setFill()
                    mark = NSRect(x: (span.lowerBound + span.upperBound - emptyDot) / 2,
                                  y: segmentsY + (segmentHeight - emptyDot) / 2, width: emptyDot, height: emptyDot)
                }
                NSBezierPath(roundedRect: mark, xRadius: mark.height / 2, yRadius: mark.height / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = showBattery
            ? String(localized: "Signal \(signalBars) of 4, iPhone battery \(filled) of 4",
                     comment: "VoiceOver description of the menu bar icon with the battery marks")
            : String(localized: "Signal \(signalBars) of 4",
                     comment: "VoiceOver description of the menu bar icon")
        return image
    }

    /// iPhone Duo–style combined glyph: an open ring for the iPhone battery, the
    /// network type in the center and 4 dots in the ring's bottom opening for the
    /// signal. Geometry follows the iPhone Duo status icon, in units of `size`:
    /// the ring's midline radius is 0.465 with 0.07 thickness, opens over the
    /// bottom 120° and fills clockwise from the lower left; the dots are 0.10
    /// wide and follow the opening's curve.
    ///
    /// Template image: the menu bar does the tinting.
    /// `isPlaceholder` draws the "no iPhone found" state: no ring, a faint
    /// center and 4 faint dots, like an iPhone with no service.
    func duoGlyph(size: CGFloat, showBattery: Bool, showNetwork: Bool, canvasHeight: CGFloat? = nil,
                  isPlaceholder: Bool = false) -> NSImage {
        let iconHeight = size * 1.04
        let height = max(canvasHeight ?? iconHeight, iconHeight)
        let originY = ((height - iconHeight) / 2).rounded()
        let bars = signalBars
        let quarters = batteryQuarters
        let label = networkLabel

        let image = NSImage(size: NSSize(width: size, height: height), flipped: false) { _ in
            // Icon-space point (x, y from the top, in units of `size`) to view space.
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: x * size, y: originY + iconHeight - y * size)
            }
            let center = point(0.5, 0.5)
            let radius = 0.465 * size
            let lineWidth = 0.07 * size

            // Angles in the icon's convention (clockwise from 12 o'clock) to AppKit's.
            func arc(from start: CGFloat, sweep: CGFloat) -> NSBezierPath {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius, startAngle: 90 - start,
                               endAngle: 90 - start - sweep, clockwise: true)
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                return path
            }

            if showBattery {
                NSColor.black.withAlphaComponent(0.25).setStroke()
                arc(from: 240, sweep: 240).stroke()
                if quarters > 0 {
                    NSColor.black.setStroke()
                    arc(from: 240, sweep: 240 * CGFloat(quarters) / 4).stroke()
                }
            }

            // Optical center for the middle content: a hair above the ring's center.
            let contentCenterY = center.y + size * 0.03
            if showNetwork {
                // Shrinks the label until it fits comfortably inside the ring ("LTE" is wider than "5G").
                var fontSize = (size * 0.36).rounded()
                var font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
                while fontSize > 5, NSAttributedString(string: label, attributes: [.font: font]).size().width > size * 0.6 {
                    fontSize -= 0.5
                    font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
                }
                let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
                let textSize = text.size()
                text.draw(at: NSPoint(x: center.x - textSize.width / 2,
                                      y: contentCenterY - font.capHeight / 2 + font.descender))
            } else if let hotspot = NSImage(systemSymbolName: "personalhotspot", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size * 0.4, weight: .semibold)) {
                // Off the hotspot there's no network label; the hotspot glyph keeps the center from looking empty.
                hotspot.draw(in: NSRect(x: center.x - hotspot.size.width / 2, y: contentCenterY - hotspot.size.height / 2,
                                        width: hotspot.size.width, height: hotspot.size.height),
                             from: .zero, operation: .sourceOver, fraction: isPlaceholder ? 0.25 : 1)
            }

            let dot = 0.10 * size
            for (index, (x, y)) in [(0.26, 0.92), (0.42, 0.975), (0.58, 0.975), (0.74, 0.92)].enumerated() {
                NSColor.black.withAlphaComponent(index < bars ? 1 : 0.25).setFill()
                let c = point(x, y)
                NSBezierPath(ovalIn: NSRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = showBattery
            ? String(localized: "Signal \(bars) of 4, iPhone battery \(quarters) of 4",
                     comment: "VoiceOver description of the menu bar icon with the battery marks")
            : String(localized: "Signal \(bars) of 4",
                     comment: "VoiceOver description of the menu bar icon")
        return image
    }

    var isBatteryLow: Bool { batteryQuarters <= 1 }

    /// Horizontal extent of each of the 4 bars inside the `cellularbars` symbol.
    /// The symbol has side padding and the bars aren't evenly spread across its
    /// width, so they're measured from a rendering once per point size.
    private static func barSpans(pointSize: CGFloat) -> [ClosedRange<CGFloat>] {
        if let cached = barSpansCache[pointSize] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "cellularbars", variableValue: 1, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return [] }

        let scale: CGFloat = 8
        let width = Int(symbol.size.width * scale), height = Int(symbol.size.height * scale)
        var spans: [ClosedRange<CGFloat>] = []
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            symbol.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()

            func isInk(_ x: Int) -> Bool {
                (0..<height).contains { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.5 }
            }
            var x = 0
            while x < width {
                guard isInk(x) else { x += 1; continue }
                let start = x
                while x < width, isInk(x) { x += 1 }
                spans.append(CGFloat(start) / scale...CGFloat(x) / scale)
            }
        }
        if spans.count != 4 {
            // Fallback: evenly spaced columns.
            let column = symbol.size.width / 4
            spans = (0..<4).map { CGFloat($0) * column + column * 0.2...CGFloat($0 + 1) * column - column * 0.2 }
        }
        barSpansCache[pointSize] = spans
        return spans
    }

    private static var barSpansCache: [CGFloat: [ClosedRange<CGFloat>]] = [:]
}
