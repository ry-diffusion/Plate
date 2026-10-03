//
//  StatusItemController.swift
//  Newtray
//
//  NSStatusItem that stands in for the system network menu: the iPhone's
//  signal while the Mac is on its hotspot, Wi-Fi or Ethernet otherwise, and a
//  menu to see and join networks.
//  Uses AppKit instead of MenuBarExtra so the symbol size can be chosen.
//

import AppKit
import CoreLocation
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
    /// Diameter of the iPhone Duo–style circle: a bit larger than the system
    /// icons, as big as the menu bar button allows without clipping the dots.
    private static let duoSize: CGFloat = 19

    private let monitor: HotspotMonitor
    private let network: NetworkMonitor
    /// The menu while it's open, so it can be rebuilt as scan results arrive.
    private weak var openMenu: NSMenu?
    private var builtMenuSignature: String?
    /// The "searching for network" animation shown while no iPhone is found,
    /// and the style and appearance it was built for.
    private var searchView: SearchAnimationView?
    private var searchViewKey: String?
    private var appearanceObservation: NSKeyValueObservation?
    /// Length of one sweep across the 4 bars, including the pause at the ends.
    private static let searchCycle: TimeInterval = 1.6
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(monitor: HotspotMonitor, network: NetworkMonitor) {
        self.monitor = monitor
        self.network = network
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        // Items are enabled by hand: headers and the current network have no action.
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        observeMonitor()
    }

    private func observeMonitor() {
        withObservationTracking {
            updateButton()
            // Keeps the open menu in step with scans, joins and the iPhone, but
            // only rebuilds it when something it shows changes: RSSI ticks every
            // second, and rebuilding that often would fight the pointer.
            let signature = menuSignature()
            if let openMenu, signature != builtMenuSignature {
                buildMenu(openMenu)
            }
        } onChange: { [weak self] in
            onMainRunLoop { [weak self] in self?.observeMonitor() }
        }
    }

    /// Everything the menu shows, so it's rebuilt only when this changes.
    private func menuSignature() -> String {
        let networks = network.networks.map { "\($0.ssid)\($0.bars)\($0.isKnown)" }.joined(separator: ",")
        let devices = monitor.devices.map { "\($0.id)\($0.signalBars)\($0.networkType)\($0.batteryQuarters)" }.joined(separator: ",")
        return [String(network.wifiPowerOn), network.currentSSID ?? "", String(WiFiNetwork.bars(rssi: network.wifiRSSI)),
                String(network.isWiFiAssociated), String(network.isScanning), String(describing: network.connection),
                network.primaryAddress ?? "", String(network.locationStatus.rawValue), String(monitor.isUsingHotspot),
                networks, devices].joined(separator: "|")
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
        // Off the iPhone's hotspot, the item shows the connection in use, like
        // the system Wi-Fi item it replaces, with the iPhone's signal before it
        // when the iPhone is nearby.
        if !monitor.isUsingHotspot {
            stopSearchAnimation()
            if style == .duo {
                // One circle, like iPhone Duo: the Mac's connection in the center,
                // the iPhone's signal in the dots and its battery in the ring
                // (faint dots and no ring when no iPhone is nearby).
                let device = monitor.device ?? HotspotDevice(id: "", name: "", model: "", networkType: 0,
                                                             signalBars: 0, batteryLevel: 0)
                button.image = device.duoGlyph(size: Self.duoSize, showBattery: showBattery && monitor.device != nil,
                                               showNetwork: false, canvasHeight: NSStatusBar.system.thickness,
                                               centerSymbol: connectionSymbol())
                button.attributedTitle = NSAttributedString()
                button.toolTip = connectionDescription()
                return
            }
            let connection = connectionGlyph()
            if let device = monitor.device, let connection, let cellular = cellularGlyph(device, style: style, showBattery: showBattery) {
                button.image = Self.sideBySide(cellular, connection, spacing: Self.glyphSpacing)
            } else {
                button.image = connection
            }
            button.attributedTitle = NSAttributedString()
            button.toolTip = connectionDescription()
            return
        }
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

    /// Gap between the iPhone's signal and the connection glyph, so the ink
    /// gap between them (~42px on a Retina menu bar) matches the one between
    /// neighboring menu bar items (36–58px, mostly 40–46px; measured on screen).
    private static let glyphSpacing: CGFloat = 17

    /// The iPhone's signal on its own (no network label), in the chosen style.
    private func cellularGlyph(_ device: HotspotDevice, style: LabelStyle, showBattery: Bool) -> NSImage? {
        let thickness = NSStatusBar.system.thickness
        return switch style {
        case .duo:
            device.duoGlyph(size: Self.duoSize, showBattery: showBattery, showNetwork: false, canvasHeight: thickness)
        case .classic:
            device.signalGlyph(pointSize: Self.symbolPointSize, showBattery: showBattery,
                               canvasHeight: thickness, verticalOffset: 0.5)
        }
    }

    /// Two template glyphs as tall as the menu bar button, side by side.
    private static func sideBySide(_ first: NSImage, _ second: NSImage, spacing: CGFloat) -> NSImage {
        let height = max(first.size.height, second.size.height)
        let image = NSImage(size: NSSize(width: first.size.width + spacing + second.size.width, height: height),
                            flipped: false) { _ in
            first.draw(in: NSRect(x: 0, y: (height - first.size.height) / 2, width: first.size.width, height: first.size.height))
            second.draw(in: NSRect(x: first.size.width + spacing, y: (height - second.size.height) / 2,
                                   width: second.size.width, height: second.size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = [first.accessibilityDescription, second.accessibilityDescription]
            .compactMap { $0 }.joined(separator: ", ")
        return image
    }

    /// The symbol for the connection in use: Wi-Fi with its signal, Ethernet,
    /// or Wi-Fi off/disconnected.
    private func connectionSymbol() -> (name: String, level: Double?) {
        switch network.connection {
        case .ethernet: ("rectangle.connected.to.line.below", nil)
        case .wifi: ("wifi", Double(WiFiNetwork.bars(rssi: network.wifiRSSI)) / 3)
        case .other, .none: network.wifiPowerOn ? ("wifi", 0) : ("wifi.slash", nil)
        }
    }

    private func connectionGlyph() -> NSImage? {
        let connection = connectionSymbol()
        return symbol(connection.name, variableValue: connection.level).map { raised($0, by: 1) }
    }

    /// Centers a symbol in a canvas as tall as the menu bar button, raised by
    /// `offset` points. 1pt puts the Wi-Fi arcs exactly where the system Wi-Fi
    /// icon sits (y 20–43px on a Retina menu bar, measured on screen).
    private func raised(_ symbol: NSImage, by offset: CGFloat) -> NSImage {
        let height = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: symbol.size.width, height: height), flipped: false) { _ in
            symbol.draw(in: NSRect(x: 0, y: ((height - symbol.size.height) / 2).rounded() + offset,
                                   width: symbol.size.width, height: symbol.size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = symbol.accessibilityDescription
        return image
    }

    private func connectionDescription() -> String {
        switch network.connection {
        case .ethernet:
            String(localized: "Ethernet", comment: "Network interface name")
        case .wifi:
            network.currentSSID ?? String(localized: "Wi-Fi", comment: "Network interface name")
        case .other, .none:
            network.wifiPowerOn
                ? String(localized: "Not connected", comment: "Menu bar tooltip: Wi-Fi on but no network")
                : String(localized: "Wi-Fi is off", comment: "Menu bar tooltip")
        }
    }

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

    /// Shows the static no-service glyph with the animated marks laid over it.
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
            onMainRunLoop { [weak self] in self?.updateButton() }
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

    private func symbol(_ name: String, variableValue: Double? = nil, pointSize: CGFloat = symbolPointSize) -> NSImage? {
        let image = if let variableValue {
            NSImage(systemSymbolName: name, variableValue: variableValue, accessibilityDescription: nil)
        } else {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return image?.withSymbolConfiguration(config)
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        openMenu = menu
        network.refreshWiFi()
        network.scan()
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
        let fresh = NSMenu()
        fresh.autoenablesItems = false
        addWiFiSection(to: fresh)
        addHotspotSection(to: fresh)
        addNetworkSections(to: fresh)
        addEthernetSection(to: fresh)
        addFooter(to: fresh)

        // An open menu doesn't shrink its window when its content gets shorter,
        // which leaves an empty gap at the bottom. Shorter updates wait for the
        // next time it opens; same-height or taller ones apply right away.
        if menu === openMenu, fresh.size.height < menu.size.height - 0.5 { return }

        builtMenuSignature = menuSignature()
        let items = fresh.items
        fresh.removeAllItems()
        menu.removeAllItems()
        items.forEach(menu.addItem)
    }

    /// Most networks shown inline under "Other Networks"; the rest go in a submenu.
    private static let inlineNetworkLimit = 8

    private func addWiFiSection(to menu: NSMenu) {
        menu.addItem(hostedItem(WiFiHeaderView(isOn: network.wifiPowerOn) { [weak self] on in
            self?.network.setWiFiPower(on)
        }))
        guard network.wifiPowerOn else { return }

        if network.isWiFiAssociated {
            let name = network.currentSSID ?? String(localized: "Wi-Fi", comment: "Network interface name")
            menu.addItem(hostedItem(NetworkRowView(name: name, level: Double(WiFiNetwork.bars(rssi: network.wifiRSSI)) / 3,
                                                   isCurrent: true)))
        }
        if !network.hasLocationAccess {
            // Without Location, macOS hides every network name.
            let denied = network.locationStatus == .denied || network.locationStatus == .restricted
            let item = NSMenuItem(title: denied
                                    ? String(localized: "Allow Location to Show Network Names…", comment: "Menu: open Location privacy settings")
                                    : String(localized: "Show Network Names…", comment: "Menu: ask for Location access"),
                                  action: #selector(requestLocation), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    private func addHotspotSection(to menu: NSMenu) {
        guard !monitor.devices.isEmpty else { return }
        menu.addItem(.sectionHeader(title: String(localized: "Personal Hotspot", comment: "Menu section")))
        let showBattery = LabelOption.battery.isEnabled
        for device in monitor.devices {
            let isConnected = monitor.isUsingHotspot
            let detail = isConnected
                ? "\(device.modelName) · \(String(localized: "Connected", comment: "Menu: the Mac is using this network"))"
                : device.modelName
            menu.addItem(hostedItem(NetworkRowView(
                name: device.name, symbol: "personalhotspot", detail: detail, isCurrent: isConnected,
                accessory: AnyView(CellularStatusView(device: device, showBattery: showBattery))),
                onSelect: isConnected ? nil : { [weak self] in self?.joinHotspot(device) }))
        }
    }

    private func addNetworkSections(to menu: NSMenu) {
        guard network.wifiPowerOn, network.hasLocationAccess else { return }
        let others = network.networks.filter { $0.ssid != network.currentSSID }
        let known = others.filter(\.isKnown)
        let unknown = others.filter { !$0.isKnown }

        if !known.isEmpty {
            menu.addItem(.sectionHeader(title: String(localized: "Known Networks", comment: "Menu section")))
            known.forEach { menu.addItem(networkItem($0)) }
        }

        menu.addItem(.sectionHeader(title: String(localized: "Other Networks", comment: "Menu: submenu of unknown networks")))
        if unknown.isEmpty {
            menu.addItem(.disabled(network.isScanning
                ? String(localized: "Scanning…", comment: "Menu: Wi-Fi scan in progress")
                : String(localized: "No other networks", comment: "Menu: empty list")))
        }
        unknown.prefix(Self.inlineNetworkLimit).forEach { menu.addItem(networkItem($0)) }
        let rest = unknown.dropFirst(Self.inlineNetworkLimit)
        if !rest.isEmpty {
            let more = NSMenuItem(title: String(localized: "More Networks", comment: "Menu: submenu with the remaining networks"),
                                  action: nil, keyEquivalent: "")
            let moreMenu = NSMenu()
            moreMenu.autoenablesItems = false
            rest.forEach { moreMenu.addItem(networkItem($0)) }
            more.submenu = moreMenu
            menu.addItem(more)
        }
    }

    private func addEthernetSection(to menu: NSMenu) {
        guard network.connection == .ethernet else { return }
        menu.addItem(.sectionHeader(title: String(localized: "Ethernet", comment: "Network interface name")))
        let detail = [network.primaryInterface, network.primaryAddress].compactMap { $0 }.joined(separator: " · ")
        menu.addItem(hostedItem(NetworkRowView(name: String(localized: "Connected", comment: "Menu: the Mac is using this network"),
                                               symbol: "rectangle.connected.to.line.below",
                                               detail: detail.isEmpty ? nil : detail, isCurrent: true)))
    }

    /// System settings, then the app's own options tucked into a submenu.
    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Network Settings…", comment: "Menu: open System Settings › Network"),
                                  action: #selector(openNetworkSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let appItem = NSMenuItem(title: "Newtray", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu()
        menu.addItem(appItem)
        menu.addItem(NSMenuItem(title: String(localized: "Quit Newtray", comment: "Menu: quit the app"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: String(localized: "Menu Bar Style", comment: "Menu section: Duo or Classic")))
        for style in LabelStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == LabelStyle.current ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.sectionHeader(title: String(localized: "On the Hotspot", comment: "Menu section: what shows while on the iPhone's hotspot")))
        let automatic = LabelOption.automatic.isEnabled
        let isDuo = LabelStyle.current == .duo
        for option in LabelOption.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(toggleOption(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option.isEnabled ? .on : .off
            // Manual options don't apply in automatic mode, and in the Duo
            // style the signal dots are always part of the circle.
            if option == .networkType && automatic || option == .signalBars && (automatic || isDuo) {
                item.isEnabled = false
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: String(localized: "Open at Login", comment: "Menu: launch the app at login"),
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        let refresh = NSMenuItem(title: String(localized: "Refresh", comment: "Menu: restart the hotspot search"),
                                 action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        return menu
    }

    // MARK: - Menu items

    /// A menu item showing a SwiftUI row. With `onSelect` it highlights like a
    /// normal item and runs it when picked.
    private func hostedItem(_ view: some View, onSelect: (() -> Void)? = nil) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuRowHostView(rootView: view, onSelect: onSelect)
        item.isEnabled = onSelect != nil
        return item
    }

    /// A network row; clicking it joins the network.
    private func networkItem(_ wifi: WiFiNetwork) -> NSMenuItem {
        hostedItem(NetworkRowView(name: wifi.ssid, level: Double(wifi.bars) / 3, isSecure: wifi.isSecure)) { [weak self] in
            self?.join(wifi)
        }
    }

    // MARK: - Actions

    private func join(_ wifi: WiFiNetwork) {
        Task {
            // Known networks have their password in the keychain; new secured ones need it typed in.
            var password: String?
            if wifi.isSecure && !wifi.isKnown {
                guard let typed = askPassword(for: wifi.ssid) else { return }
                password = typed
            }
            do {
                try await network.join(wifi, password: password)
            } catch {
                // A saved password can be stale: ask once and retry.
                if wifi.isSecure, password == nil, let typed = askPassword(for: wifi.ssid) {
                    do { try await network.join(wifi, password: typed) } catch { show(error, joining: wifi.ssid) }
                } else {
                    show(error, joining: wifi.ssid)
                }
            }
        }
    }

    private func joinHotspot(_ device: HotspotDevice) {
        Task {
            do {
                let credentials = try await monitor.enableHotspot(on: device)
                try await network.join(ssid: credentials.ssid, password: credentials.password)
            } catch {
                show(error, joining: device.name)
            }
        }
    }

    /// Password sheet for a secured network; nil when cancelled.
    private func askPassword(for ssid: String) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "The Wi-Fi network “\(ssid)” requires a password.",
                                   comment: "Password prompt title")
        alert.addButton(withTitle: String(localized: "Join", comment: "Password prompt: confirm"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Password prompt: cancel"))
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = String(localized: "Password", comment: "Password prompt: field placeholder")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    private func show(_ error: Error, joining name: String) {
        NSApp.activate()
        let alert = NSAlert(error: error)
        alert.messageText = String(localized: "Couldn’t join “\(name)”.", comment: "Join error title")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func requestLocation() {
        if network.locationStatus == .notDetermined {
            NSApp.activate()
            network.requestLocationAccess()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
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

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
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
