//
//  StatusItemController.swift
//  Newtray
//
//  NSStatusItem with the signal bars (SF Symbol) and network type (native title).
//  Uses AppKit instead of MenuBarExtra so the symbol size can be chosen.
//

import AppKit
import Observation
import SwiftUI

/// What shows in the menu bar. Each option becomes a checkable menu item.
enum LabelOption: String, CaseIterable {
    /// Signal bars always; network type only while the Mac is on the hotspot.
    case automatic, signalBars, networkType
    /// Independent of the mode (automatic or manual) and off by default.
    case battery

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic", comment: "Menu bar display option")
        case .signalBars: String(localized: "Signal Bars", comment: "Menu bar display option")
        case .networkType: String(localized: "Network Type (5G/LTE)", comment: "Menu bar display option")
        case .battery: String(localized: "iPhone Battery", comment: "Menu bar display option")
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? (self != .battery) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    private var storageKey: String { "show.\(rawValue)" }
}

final class StatusItemController: NSObject, NSMenuDelegate {
    /// Symbol size, chosen to match the height of the system icons (battery,
    /// Control Center). NSStatusItem's default would be 13pt.
    private static let symbolPointSize: CGFloat = 15
    /// Extra room to the right of the bars for 6pt between them and "5G" (the
    /// button already puts ~5pt between image and title; measured on screen).
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
            // Bars always; the network text only while the Mac is on the hotspot.
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
                                              // Lines up the bars' center with the system Wi-Fi icon (measured on screen).
                                              verticalOffset: 0.5)
        } else {
            button.image = nil
        }
        button.attributedTitle = showNetwork ? title(device.networkLabel) : NSAttributedString()
        button.toolTip = String(
            localized: "\(device.name): \(device.networkLabel), signal \(device.signalBars)/4, battery \(device.batteryQuarters)/4",
            comment: "Menu bar item tooltip: iPhone name, network type, signal and battery levels")
    }

    /// "5G" in bold, in the menu bar font.
    private func title(_ text: String) -> NSAttributedString {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        // The button's default title sits 0.5pt below the clock's text.
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
            menu.addItem(.disabled(String(localized: "Sharing.framework unavailable",
                                          comment: "Menu: the private framework could not be loaded")))
        } else if monitor.devices.isEmpty {
            menu.addItem(.disabled(String(localized: "No iPhone with Personal Hotspot nearby",
                                          comment: "Menu: no hotspot device found")))
        }
        for device in monitor.devices {
            let item = NSMenuItem()
            let header = NSHostingView(rootView: DeviceHeaderView(device: device, showBattery: LabelOption.battery.isEnabled))
            header.frame.size = header.fittingSize
            item.view = header
            menu.addItem(item)
        }
        if let lastUpdate = monitor.lastUpdate {
            let time = lastUpdate.formatted(.dateTime.hour().minute().second())
            menu.addItem(.disabled(String(localized: "Updated \(time)", comment: "Menu: time of the last update")))
        }

        menu.addItem(.separator())
        let optionsItem = NSMenuItem(title: String(localized: "Show in Menu Bar", comment: "Menu: display options submenu"),
                                     action: nil, keyEquivalent: "")
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
                    ? String(localized: "On the hotspot: bars and network", comment: "Automatic mode state")
                    : String(localized: "Off the hotspot: bars only", comment: "Automatic mode state")))
                optionsMenu.addItem(.separator())
            case .signalBars, .networkType:
                // Manual options don't apply in automatic mode, so they're disabled.
                if automatic {
                    item.action = nil
                }
                optionsMenu.addItem(item)
            case .battery:
                // Applies in both modes.
                optionsMenu.addItem(.separator())
                optionsMenu.addItem(item)
            }
        }
        optionsItem.submenu = optionsMenu
        menu.addItem(optionsItem)

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: String(localized: "Refresh", comment: "Menu: restart the hotspot search"),
                                 action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(NSMenuItem(title: String(localized: "Quit", comment: "Menu: quit the app"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
