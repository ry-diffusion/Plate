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

    /// Signal bars with, optionally, the iPhone battery as a row of 4 dots below
    /// (one under each bar), lit left to right by quarter. No percentage: the
    /// iPhone only advertises its battery in quarters.
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

        // At 15pt: 2pt dots, 1pt below the bars. The menu bar button clips
        // ~1.5pt off the bottom of the image, so they can't be any bigger.
        let dot = (pointSize * 0.135).rounded()
        let spacing = (pointSize / 15).rounded()
        let compactHeight = bars.size.height + (showBattery ? dot + spacing : 0)
        let height = max(canvasHeight ?? compactHeight, compactHeight)
        let barsY = canvasHeight == nil
            ? height - bars.size.height
            : ((height - bars.size.height) / 2).rounded() + verticalOffset
        let dotsY = barsY - spacing - dot
        let filled = batteryQuarters

        let image = NSImage(size: NSSize(width: bars.size.width + trailingPadding, height: height), flipped: false) { _ in
            bars.draw(in: NSRect(x: 0, y: barsY, width: bars.size.width, height: bars.size.height))
            guard showBattery else { return true }
            let column = bars.size.width / 4
            for index in 0..<4 {
                NSColor.black.withAlphaComponent(index < filled ? 1 : 0.3).setFill()
                let x = column * (CGFloat(index) + 0.5) - dot / 2
                NSBezierPath(ovalIn: NSRect(x: x, y: dotsY, width: dot, height: dot)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = showBattery
            ? String(localized: "Signal \(signalBars) of 4, iPhone battery \(filled) of 4",
                     comment: "VoiceOver description of the menu bar icon with the battery dots")
            : String(localized: "Signal \(signalBars) of 4",
                     comment: "VoiceOver description of the menu bar icon")
        return image
    }

    var isBatteryLow: Bool { batteryQuarters <= 1 }
}
