//
//  HotspotDevice+Model.swift
//  Newtray
//
//  Nome comercial e ícone do aparelho a partir do identificador de modelo
//  ("iPhone18,1" → "iPhone 17 Pro"), usando os UTIs que o CoreTypes do macOS
//  registra para cada modelo.
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

    /// "iPhone 17 Pro"; cai no identificador cru se o macOS não conhece o modelo.
    var modelName: String {
        modelType?.localizedDescription ?? model
    }

    var modelIcon: NSImage {
        if let modelType {
            return NSWorkspace.shared.icon(for: modelType)
        }
        return NSImage(systemSymbolName: "iphone", accessibilityDescription: nil) ?? NSImage()
    }

    /// O iPhone anuncia a bateria em quartos (0, 25, 50, 75, 100), então ela é
    /// mostrada como nível de 0 a 4, nunca como porcentagem.
    var batteryQuarters: Int {
        min(max(Int((Double(batteryLevel) / 25).rounded()), 0), 4)
    }

    /// Bateria do iPhone como 4 pontos em coluna, acesos de baixo pra cima
    /// conforme os quartos. Os apagados ficam esmaecidos, como as barras
    /// inativas da torre.
    ///
    /// Desenhado com `labelColor` na hora do desenho, então acompanha a
    /// aparência de onde estiver (o título do NSStatusBarButton não pinta
    /// imagens template dentro de text attachments).
    func batteryGlyph(height: CGFloat) -> NSImage {
        // 4 pontos de 20% da altura com 3 vãos iguais (~0,8pt em 12,5pt).
        let dot = height * 0.2
        let gap = (height - dot * 4) / 3
        let filled = batteryQuarters
        let image = NSImage(size: NSSize(width: dot, height: height), flipped: false) { _ in
            for index in 0..<4 {
                let color = index < filled ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.3)
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: CGFloat(index) * (dot + gap), width: dot, height: dot)).fill()
            }
            return true
        }
        image.accessibilityDescription = "Bateria do iPhone: \(filled) de 4"
        return image
    }

    var isBatteryLow: Bool { batteryQuarters <= 1 }
}
