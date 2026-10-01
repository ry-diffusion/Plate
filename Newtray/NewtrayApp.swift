//
//  NewtrayApp.swift
//  Newtray
//
//  Created by Moizes Sousa on 01/10/26.
//

import SwiftUI

@main
struct NewtrayApp: App {
    @State private var monitor = HotspotMonitor()

    var body: some Scene {
        MenuBarExtra {
            HotspotMenu(monitor: monitor)
        } label: {
            StatusLabel(device: monitor.device)
        }
    }
}

/// O que aparece na status bar. Cada opção vira um toggle no menu.
enum LabelOption: String, CaseIterable, Identifiable {
    case networkType, signalBars

    var id: String { rawValue }

    var title: String {
        switch self {
        case .networkType: "Tipo de rede (5G/LTE)"
        case .signalBars: "Barras de sinal"
        }
    }

    var storageKey: String { "show.\(rawValue)" }
}

struct StatusLabel: View {
    let device: HotspotDevice?

    @AppStorage(LabelOption.networkType.storageKey) private var showNetwork = true
    @AppStorage(LabelOption.signalBars.storageKey) private var showBars = true

    var body: some View {
        if let device, let image = renderLabel(device) {
            // O MenuBarExtra só renderiza um Image + um Text, então o label
            // inteiro é desenhado numa imagem template.
            Image(nsImage: image)
        } else {
            Image(systemName: device == nil ? "personalhotspot.slash" : "personalhotspot")
        }
    }

    private func renderLabel(_ device: HotspotDevice) -> NSImage? {
        var parts: [Text] = []
        if showBars {
            parts.append(Text(Image(systemName: "cellularbars", variableValue: Double(device.signalBars) / 4)))
        }
        if showNetwork {
            parts.append(Text(device.networkLabel))
        }
        guard !parts.isEmpty else { return nil }

        let renderer = ImageRenderer(content: parts.joined(separator: "  ").font(.system(size: 13, weight: .medium)))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = true
        return image
    }
}

struct HotspotMenu: View {
    let monitor: HotspotMonitor

    var body: some View {
        if !monitor.isAvailable {
            Text("Sharing.framework indisponível")
        } else if monitor.devices.isEmpty {
            Text("Nenhum iPhone com hotspot por perto")
        }
        ForEach(monitor.devices) { device in
            Section(device.name) {
                Text("Rede: \(device.networkLabel) · \(device.signalBars)/4 barras")
                if !device.model.isEmpty {
                    Text("Modelo: \(device.model)")
                }
            }
        }
        if let lastUpdate = monitor.lastUpdate {
            Text("Atualizado \(lastUpdate, format: .dateTime.hour().minute().second())")
        }
        Divider()
        Menu("Mostrar na barra") {
            ForEach(LabelOption.allCases) { option in
                OptionToggle(option: option)
            }
        }
        Divider()
        Button("Atualizar") { monitor.restartBrowsing() }
            .keyboardShortcut("r")
        Button("Sair") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct OptionToggle: View {
    let option: LabelOption
    @AppStorage private var isOn: Bool

    init(option: LabelOption) {
        self.option = option
        _isOn = AppStorage(wrappedValue: true, option.storageKey)
    }

    var body: some View {
        Toggle(option.title, isOn: $isOn)
    }
}

private extension [Text] {
    func joined(separator: String) -> Text {
        guard let first else { return Text("") }
        return dropFirst().reduce(first) { Text("\($0)\(separator)\($1)") }
    }
}
