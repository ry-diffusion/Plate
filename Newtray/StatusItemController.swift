//
//  StatusItemController.swift
//  Newtray
//
//  NSStatusItem com a torre (símbolo SF) e o tipo de rede (título nativo).
//  Usa AppKit em vez de MenuBarExtra pra poder escolher o tamanho do símbolo.
//

import AppKit
import Observation
import SwiftUI

/// O que aparece na status bar. Cada opção vira um item marcável no menu.
enum LabelOption: String, CaseIterable {
    /// Torre sempre; tipo de rede só quando o Mac está usando o hotspot.
    case automatic, signalBars, networkType
    /// Independente do modo (automático ou manual) e desligada por padrão.
    case battery

    var title: String {
        switch self {
        case .automatic: "Automático"
        case .signalBars: "Barras de sinal"
        case .networkType: "Tipo de rede (5G/LTE)"
        case .battery: "Bateria do iPhone"
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? (self != .battery) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    private var storageKey: String { "show.\(rawValue)" }
}

final class StatusItemController: NSObject, NSMenuDelegate {
    /// Tamanho do símbolo, escolhido pra igualar a altura dos ícones do sistema
    /// (bateria, Control Center). O padrão do NSStatusItem seria 13pt.
    private static let symbolPointSize: CGFloat = 15

    private let monitor: HotspotMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(monitor: HotspotMonitor) {
        self.monitor = monitor
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        observeMonitor()
    }

    private func observeMonitor() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeMonitor() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let showBars: Bool
        let showNetwork: Bool
        let showBattery = LabelOption.battery.isEnabled
        if LabelOption.automatic.isEnabled {
            // Torre sempre; o texto da rede só quando o Mac usa o hotspot.
            showBars = true
            showNetwork = monitor.isUsingHotspot
        } else {
            showBars = LabelOption.signalBars.isEnabled
            showNetwork = LabelOption.networkType.isEnabled
        }

        guard let device = monitor.device, showBars || showNetwork || showBattery else {
            button.image = symbol(monitor.device == nil ? "personalhotspot.slash" : "personalhotspot")
            button.attributedTitle = NSAttributedString()
            return
        }
        button.image = showBars ? symbol("cellularbars", variableValue: Double(device.signalBars) / 4) : nil
        button.attributedTitle = title(network: showNetwork ? device.networkLabel : nil,
                                       battery: showBattery ? device : nil)
        button.toolTip = "\(device.name): \(device.networkLabel), sinal \(device.signalBars)/4, bateria \(device.batteryQuarters)/4"
    }

    /// Título nativo do botão: "⁞ 5G", logo depois da torre. A bateria vai como
    /// 4 pontos, sem porcentagem, porque o iPhone só anuncia o nível em quartos.
    private func title(network: String?, battery device: HotspotDevice?) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        // O título padrão do botão fica 0,5pt abaixo do texto do relógio.
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 0.5]
        let title = NSMutableAttributedString()
        if let device {
            // Mesma altura da torre (~12,5pt).
            let glyph = device.batteryGlyph(height: 12.5)
            let attachment = NSTextAttachment()
            attachment.image = glyph
            // Alinha os pontos com a base e o topo da torre.
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - glyph.size.height) / 2,
                                       width: glyph.size.width, height: glyph.size.height)
            title.append(NSAttributedString(attachment: attachment))
        }
        if let network {
            if title.length > 0 {
                title.append(NSAttributedString(string: " ", attributes: attributes))
            }
            title.append(NSAttributedString(string: network, attributes: attributes))
        }
        return title
    }

    private func symbol(_ name: String, variableValue: Double? = nil) -> NSImage? {
        let image = if let variableValue {
            NSImage(systemSymbolName: name, variableValue: variableValue, accessibilityDescription: nil)
        } else {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        let config = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .regular)
        return image?.withSymbolConfiguration(config)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !monitor.isAvailable {
            menu.addItem(.disabled("Sharing.framework indisponível"))
        } else if monitor.devices.isEmpty {
            menu.addItem(.disabled("Nenhum iPhone com hotspot por perto"))
        }
        for device in monitor.devices {
            let item = NSMenuItem()
            let header = NSHostingView(rootView: DeviceHeaderView(device: device, showBattery: LabelOption.battery.isEnabled))
            header.frame.size = header.fittingSize
            item.view = header
            menu.addItem(item)
        }
        if let lastUpdate = monitor.lastUpdate {
            menu.addItem(.disabled("Atualizado \(lastUpdate.formatted(.dateTime.hour().minute().second()))"))
        }

        menu.addItem(.separator())
        let optionsItem = NSMenuItem(title: "Mostrar na barra", action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        let automatic = LabelOption.automatic.isEnabled
        for option in LabelOption.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(toggleOption(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option.isEnabled ? .on : .off
            switch option {
            case .automatic:
                optionsMenu.addItem(item)
                optionsMenu.addItem(.disabled(monitor.isUsingHotspot
                    ? "Usando o hotspot: torre e rede"
                    : "Fora do hotspot: só a torre"))
                optionsMenu.addItem(.separator())
            case .signalBars, .networkType:
                // No automático as opções manuais não valem, então ficam desativadas.
                if automatic {
                    item.action = nil
                }
                optionsMenu.addItem(item)
            case .battery:
                // Vale nos dois modos.
                optionsMenu.addItem(.separator())
                optionsMenu.addItem(item)
            }
        }
        optionsItem.submenu = optionsMenu
        menu.addItem(optionsItem)

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Atualizar", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleOption(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = LabelOption(rawValue: raw) else { return }
        option.isEnabled.toggle()
        updateButton()
    }

    @objc private func refresh() {
        monitor.restartBrowsing()
    }
}

private extension NSMenuItem {
    static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
