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

/// How the menu bar item is drawn.
enum LabelStyle: String, CaseIterable {
    /// iPhone Duo–style circle: battery ring, network type in the center and
    /// signal dots below.
    case duo
    /// Signal bars with the network type beside them and the battery marks below.
    case classic

    var title: String {
        switch self {
        case .duo: String(localized: "iPhone Duo", comment: "Menu bar style option")
        case .classic: String(localized: "Classic", comment: "Menu bar style option")
        }
    }

    static var current: LabelStyle {
        get { UserDefaults.standard.string(forKey: "style").flatMap(LabelStyle.init(rawValue:)) ?? .duo }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "style") }
    }
}

final class StatusItemController: NSObject, NSMenuDelegate {
    /// Symbol size, chosen to match the height of the system icons (battery,
    /// Control Center). NSStatusItem's default would be 13pt.
    private static let symbolPointSize: CGFloat = 15
    /// Extra room to the right of the bars for 6pt between them and "5G" (the
    /// button already puts ~5pt between image and title; measured on screen).
    private static let titleSpacing: CGFloat = 0.5
    /// Diameter of the iPhone Duo–style circle, close to the system icons' height.
    private static let duoSize: CGFloat = 17.5

    private let monitor: HotspotMonitor
    /// The "searching for network" animation shown while no iPhone is found,
    /// and the style and appearance it was built for.
    private var searchView: SearchAnimationView?
    private var searchViewKey: String?
    private var appearanceObservation: NSKeyValueObservation?
    /// Length of one sweep across the 4 bars, including the pause at the ends.
    private static let searchCycle: TimeInterval = 1.6
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

        let style = LabelStyle.current
        guard let device = monitor.device else {
            // No iPhone found: short faint bars (or dots), like an iPhone with
            // no service. Only while the Mac is on the hotspot does a wave sweep
            // across them, the iPhone's "searching for network" look; otherwise
            // there's nothing being looked for, so they stay still.
            if monitor.isUsingHotspot {
                startSearchAnimation(style: style)
            } else {
                stopSearchAnimation()
                button.image = noServiceGlyph(style: style)
            }
            button.attributedTitle = NSAttributedString()
            button.toolTip = String(localized: "No iPhone with Personal Hotspot nearby",
                                    comment: "Menu: no hotspot device found")
            return
        }
        stopSearchAnimation()
        guard style == .duo || showBars || showNetwork || showBattery else {
            button.image = symbol("personalhotspot")
            button.attributedTitle = NSAttributedString()
            return
        }
        if style == .duo {
            // Everything lives in the circle; the signal dots are part of it.
            button.image = device.duoGlyph(size: Self.duoSize, showBattery: showBattery, showNetwork: showNetwork,
                                           canvasHeight: NSStatusBar.system.thickness)
            button.attributedTitle = NSAttributedString()
        } else if showBars {
            button.image = device.signalGlyph(pointSize: Self.symbolPointSize, showBattery: showBattery,
                                              trailingPadding: showNetwork ? Self.titleSpacing : 0,
                                              canvasHeight: NSStatusBar.system.thickness,
                                              // Lines up the bars' center with the system Wi-Fi icon (measured on screen).
                                              verticalOffset: 0.5)
        } else {
            button.image = nil
        }
        if style == .classic {
            button.attributedTitle = showNetwork ? title(device.networkLabel) : NSAttributedString()
        }
        button.toolTip = String(
            localized: "\(device.name): \(device.networkLabel), signal \(device.signalBars)/4, battery \(device.batteryQuarters)/4",
            comment: "Menu bar item tooltip: iPhone name, network type, signal and battery levels")
    }

    /// Shows the static no-service glyph with the animated marks laid over it.
    /// The static no-service glyph: short faint bars (Classic) or faint dots (Duo).
    private func noServiceGlyph(style: LabelStyle) -> NSImage? {
        let thickness = NSStatusBar.system.thickness
        let none = HotspotDevice(id: "", name: "", model: "", networkType: 0, signalBars: 0, batteryLevel: 0)
        return switch style {
        case .duo:
            none.duoGlyph(size: Self.duoSize, showBattery: false, showNetwork: false,
                          canvasHeight: thickness, isPlaceholder: true)
        case .classic:
            none.signalGlyph(pointSize: Self.symbolPointSize, showBattery: false,
                             canvasHeight: thickness, verticalOffset: 0.5)
        }
    }

    private func startSearchAnimation(style: LabelStyle) {
        guard let button = statusItem.button else { return }
        let thickness = NSStatusBar.system.thickness
        let base = noServiceGlyph(style: style)
        let marks: [SearchAnimationView.Mark] = switch style {
        case .duo:
            HotspotDevice.duoDotRects(size: Self.duoSize, canvasHeight: thickness)
                .map { .init(rest: $0, peak: $0) }
        case .classic:
            HotspotDevice.classicSearchBars(pointSize: Self.symbolPointSize, canvasHeight: thickness,
                                            verticalOffset: 0.5)
                .map { .init(rest: $0.stub, peak: $0.full) }
        }
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key = "\(style.rawValue)-\(isDark)"
        guard searchViewKey != key, let base else { return }
        button.image = base
        searchView?.removeFromSuperview()
        button.layoutSubtreeIfNeeded()
        // The button centers its image; the overlay sits exactly on it.
        let frame = NSRect(x: ((button.bounds.width - base.size.width) / 2).rounded(),
                           y: ((button.bounds.height - base.size.height) / 2).rounded(),
                           width: base.size.width, height: base.size.height)
        let view = SearchAnimationView(frame: frame, marks: marks, color: isDark ? .white : .black,
                                       cycle: Self.searchCycle)
        view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        button.addSubview(view)
        searchView = view
        searchViewKey = key

        // Rebuilds with the right color when the menu bar turns light or dark.
        // Only on a real change: the button reports appearance updates for
        // unrelated reasons too, and rebuilding on each would loop.
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] button, _ in
            let nowDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            guard nowDark != isDark else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateButton() }
            }
        }
    }

    private func stopSearchAnimation() {
        searchView?.removeFromSuperview()
        searchView = nil
        searchViewKey = nil
        appearanceObservation = nil
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
            let header = NSHostingView(rootView: DeviceHeaderView(device: device, style: LabelStyle.current,
                                                                  showBattery: LabelOption.battery.isEnabled))
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
        for style in LabelStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == LabelStyle.current ? .on : .off
            optionsMenu.addItem(item)
        }
        optionsMenu.addItem(.separator())

        let automatic = LabelOption.automatic.isEnabled
        let isDuo = LabelStyle.current == .duo
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
                // In the Duo style the signal dots are always part of the circle.
                if automatic || (isDuo && option == .signalBars) {
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

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = LabelStyle(rawValue: raw) else { return }
        LabelStyle.current = style
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
