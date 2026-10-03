//
//  HotspotDevice+Model.swift
//  Plate
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
    /// With 0 signal the bars are drawn like an iPhone with no service: 4 short
    /// bars, all as tall as the first one. `searchPhase` (0–1) sweeps a wave
    /// across them for the "searching for network" animation: as it passes, each
    /// bar grows to its full height and brightens, then shrinks back.
    func signalGlyph(pointSize: CGFloat, showBattery: Bool, trailingPadding: CGFloat = 0,
                     canvasHeight: CGFloat? = nil, verticalOffset: CGFloat = 0,
                     searchPhase: CGFloat? = nil) -> NSImage? {
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
        let barRects = Self.barRects(pointSize: pointSize)
        let noService = signalBars == 0 && barRects.count == 4

        let image = NSImage(size: NSSize(width: bars.size.width + trailingPadding, height: height), flipped: false) { _ in
            if noService {
                let stub = barRects[0]
                for (index, bar) in barRects.enumerated() {
                    NSColor.black.withAlphaComponent(Self.searchAlpha(index: index, phase: searchPhase, base: 0.3)).setFill()
                    let grown = stub.height + Self.searchGlow(index: index, phase: searchPhase) * (bar.height - stub.height)
                    let rect = NSRect(x: bar.minX, y: barsY + stub.minY, width: bar.width, height: grown)
                    NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
                }
            } else {
                bars.draw(in: NSRect(x: 0, y: barsY, width: bars.size.width, height: bars.size.height))
            }
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
    /// `searchPhase` (0–1) sweeps a soft glow across the signal dots, for the
    /// "searching for network" animation.
    ///
    /// `centerSymbol` puts a symbol in the middle instead of the network label,
    /// like the iPhone Duo's Wi-Fi fan: the Mac's Wi-Fi with its signal, or
    /// Ethernet, while it isn't on the hotspot.
    func duoGlyph(size: CGFloat, showBattery: Bool, showNetwork: Bool, canvasHeight: CGFloat? = nil,
                  isPlaceholder: Bool = false, searchPhase: CGFloat? = nil,
                  centerSymbol: (name: String, level: Double?)? = nil) -> NSImage {
        let iconHeight = size * 1.04
        let height = max(canvasHeight ?? iconHeight, iconHeight)
        // The menu bar button clips ~1.5pt off the bottom, so the dots keep at
        // least that much room below them.
        let originY = max(((height - iconHeight) / 2).rounded(), canvasHeight == nil ? 0 : 1.5)
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
            } else if let centerSymbol {
                let base = if let level = centerSymbol.level {
                    NSImage(systemSymbolName: centerSymbol.name, variableValue: level, accessibilityDescription: nil)
                } else {
                    NSImage(systemSymbolName: centerSymbol.name, accessibilityDescription: nil)
                }
                // Sized so the Wi-Fi fan spans ~56% of the circle, as on iPhone Duo;
                // other glyphs (Ethernet) are boxier, so they get a smaller size.
                let scale: CGFloat = centerSymbol.name.hasPrefix("wifi") ? 0.44 : 0.36
                if let symbol = base?.withSymbolConfiguration(.init(pointSize: size * scale, weight: .semibold)) {
                    symbol.draw(in: NSRect(x: center.x - symbol.size.width / 2, y: contentCenterY - symbol.size.height / 2,
                                           width: symbol.size.width, height: symbol.size.height),
                                from: .zero, operation: .sourceOver, fraction: isPlaceholder ? 0.25 : 1)
                }
            } else if let hotspot = NSImage(systemSymbolName: "personalhotspot", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size * 0.4, weight: .semibold)) {
                // Off the hotspot there's no network label; the hotspot glyph keeps the center from looking empty.
                hotspot.draw(in: NSRect(x: center.x - hotspot.size.width / 2, y: contentCenterY - hotspot.size.height / 2,
                                        width: hotspot.size.width, height: hotspot.size.height),
                             from: .zero, operation: .sourceOver, fraction: isPlaceholder ? 0.25 : 1)
            }

            let dot = 0.10 * size
            for (index, (x, y)) in [(0.26, 0.92), (0.42, 0.975), (0.58, 0.975), (0.74, 0.92)].enumerated() {
                NSColor.black.withAlphaComponent(index < bars ? 1 : Self.searchAlpha(index: index, phase: searchPhase, base: 0.25)).setFill()
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
    private static func barSpans(pointSize: CGFloat) -> [ClosedRange<CGFloat>] {
        barRects(pointSize: pointSize).map { $0.minX...$0.maxX }
    }

    /// Geometry of the Classic "searching" bars inside `signalGlyph`'s image
    /// (with `canvasHeight`, no battery): each bar's short no-service frame and
    /// its full frame in the signal staircase. Used to animate them with Core
    /// Animation instead of redrawing the image.
    static func classicSearchBars(pointSize: CGFloat, canvasHeight: CGFloat,
                                  verticalOffset: CGFloat) -> [(stub: NSRect, full: NSRect)] {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let rects = barRects(pointSize: pointSize)
        guard rects.count == 4,
              let symbol = NSImage(systemSymbolName: "cellularbars", variableValue: 0, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return [] }
        let barsY = ((canvasHeight - symbol.size.height) / 2).rounded() + verticalOffset
        let stub = rects[0]
        return rects.map { bar in
            (NSRect(x: bar.minX, y: barsY + stub.minY, width: bar.width, height: stub.height),
             NSRect(x: bar.minX, y: barsY + stub.minY, width: bar.width, height: bar.height))
        }
    }

    /// Frames of the 4 signal dots inside `duoGlyph`'s image (with `canvasHeight`).
    static func duoDotRects(size: CGFloat, canvasHeight: CGFloat) -> [NSRect] {
        let iconHeight = size * 1.04
        let height = max(canvasHeight, iconHeight)
        let originY = max(((height - iconHeight) / 2).rounded(), 1.5)
        let dot = 0.10 * size
        return [(0.26, 0.92), (0.42, 0.975), (0.58, 0.975), (0.74, 0.92)].map { x, y in
            NSRect(x: x * size - dot / 2, y: originY + iconHeight - y * size - dot / 2, width: dot, height: dot)
        }
    }

    /// Opacity of bar or dot `index` (0–3) during the searching animation: a
    /// Gaussian glow whose center travels from before the first to past the
    /// last one over a cycle, so every mark fades in and out smoothly and the
    /// ends of the cycle work as a short pause with nothing lit.
    static func searchAlpha(index: Int, phase: CGFloat?, base: CGFloat) -> CGFloat {
        base + (1 - base) * searchGlow(index: index, phase: phase)
    }

    /// 0–1 strength of the searching wave at bar or dot `index`.
    static func searchGlow(index: Int, phase: CGFloat?) -> CGFloat {
        guard let phase else { return 0 }
        let head = -1 + phase * 5
        let distance = CGFloat(index) - head
        return exp(-(distance * distance) / (2 * 0.5 * 0.5))
    }

    /// Frame of each of the 4 bars inside the `cellularbars` symbol (y up). The
    /// symbol has padding and the bars aren't evenly spread across its width,
    /// so they're measured from a rendering once per point size.
    private static func barRects(pointSize: CGFloat) -> [NSRect] {
        if let cached = barRectsCache[pointSize] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "cellularbars", variableValue: 1, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return [] }

        let scale: CGFloat = 8
        let width = Int(symbol.size.width * scale), height = Int(symbol.size.height * scale)
        var rects: [NSRect] = []
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0) {
            // Drawn at its real point size into a high-resolution bitmap: drawing
            // it into a rect 8× larger makes SF Symbols render the bars with the
            // proportions of a bigger size, which are taller and offset.
            rep.size = symbol.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
            NSGraphicsContext.restoreGraphicsState()

            func isInk(_ x: Int, _ y: Int) -> Bool { (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 }
            var x = 0
            while x < width {
                guard (0..<height).contains(where: { isInk(x, $0) }) else { x += 1; continue }
                let start = x
                while x < width, (0..<height).contains(where: { isInk(x, $0) }) { x += 1 }
                // Bitmap rows count from the top.
                let rows = (0..<height).filter { y in (start..<x).contains { isInk($0, y) } }
                rects.append(NSRect(x: CGFloat(start) / scale, y: CGFloat(height - rows.last! - 1) / scale,
                                    width: CGFloat(x - start) / scale, height: CGFloat(rows.count) / scale))
            }
        }
        if rects.count != 4 {
            // Fallback: evenly spaced columns of growing height.
            let column = symbol.size.width / 4, unit = symbol.size.height / 4
            rects = (0..<4).map { NSRect(x: CGFloat($0) * column + column * 0.2, y: 0, width: column * 0.6,
                                         height: unit * CGFloat($0 + 1)) }
        }
        barRectsCache[pointSize] = rects
        return rects
    }

    private static var barRectsCache: [CGFloat: [NSRect]] = [:]
}
