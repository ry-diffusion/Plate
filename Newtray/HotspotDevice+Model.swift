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

    /// Torre de sinal com, opcionalmente, a bateria do iPhone como 4 pontos em
    /// fileira embaixo (um sob cada barra), acesos da esquerda pra direita
    /// conforme os quartos. Sem porcentagem: o iPhone só anuncia a bateria em
    /// quartos.
    ///
    /// Com `canvasHeight` (a altura do botão da status bar), a torre fica
    /// sempre no centro, com ou sem bateria, e os pontos usam o espaço que
    /// sobra embaixo. `verticalOffset` sobe a torre (em pontos) pra acertar o
    /// centro óptico com os outros itens. Sem `canvasHeight`, a imagem fica
    /// justa (pra usar no menu).
    /// Imagem template: quem pinta é a menu bar.
    func signalGlyph(pointSize: CGFloat, showBattery: Bool, trailingPadding: CGFloat = 0,
                     canvasHeight: CGFloat? = nil, verticalOffset: CGFloat = 0) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let bars = NSImage(systemSymbolName: "cellularbars", variableValue: Double(signalBars) / 4,
                                 accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }

        // Em 15pt: pontos de 2pt a 1pt da torre. O botão da status bar corta
        // ~1,5pt da base da imagem, então não dá pra ser maior que isso.
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
            ? "Sinal \(signalBars) de 4, bateria do iPhone \(filled) de 4"
            : "Sinal \(signalBars) de 4"
        return image
    }

    var isBatteryLow: Bool { batteryQuarters <= 1 }
}
