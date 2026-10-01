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
    /// Respiro extra à direita da torre pra dar 6pt entre a torre e o "5G" (o
    /// botão já põe ~5pt entre a imagem e o título; medido na tela).
    private static let titleSpacing: CGFloat = 0.5

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
        if showBars {
            button.image = device.signalGlyph(pointSize: Self.symbolPointSize, showBattery: showBattery,
                                              trailingPadding: showNetwork ? Self.titleSpacing : 0,
                                              canvasHeight: NSStatusBar.system.thickness,
                                              // Alinha o centro da torre com o do Wi-Fi do sistema (medido na tela).
                                              verticalOffset: 0.5)
        } else {
            button.image = nil
        }
        button.attributedTitle = showNetwork ? title(device.networkLabel) : NSAttributedString()
        button.toolTip = "\(device.name): \(device.networkLabel), sinal \(device.signalBars)/4, bateria \(device.batteryQuarters)/4"
    }

    /// "5G" em bold, na fonte da menu bar.
    private func title(_ text: String) -> NSAttributedString {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        // O título padrão do botão fica 0,5pt abaixo do texto do relógio.
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .baselineOffset: 0.5,
        ])
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
