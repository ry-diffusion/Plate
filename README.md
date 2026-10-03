# Newtray

A macOS menu bar app that replaces the system Wi-Fi menu: it shows Wi-Fi, Ethernet and your iPhone's Instant Hotspot (signal, cellular network type like 5G/LTE, and battery), lists nearby networks and joins them.

In the menu bar, the item shows the connection in use: Wi-Fi arcs with the signal, an Ethernet glyph, or Wi-Fi off. While the Mac is on the iPhone's hotspot it shows the iPhone's cellular signal instead, in one of two styles, picked under *Newtray › Menu Bar Style*:

- **iPhone Duo** (default), after the iPhone Duo's circular status icon: an open ring for the iPhone battery, the network type (5G/LTE) in the center and 4 dots in the ring's opening for the signal. Off the hotspot, the center shows the Personal Hotspot glyph.
- **Classic**: signal bars with the network type beside them and the battery marks below.

```
▂▄▆█ 5G          (Classic, on the hotspot)
▂▄▆█             (Classic, on another Wi-Fi network)
▂▄▆█ 5G
▬▬▬·             (Classic with iPhone Battery on: one mark under each bar)
```

When no iPhone is found, both styles show short faint bars (or faint dots), like an iPhone with no service. While the Mac is on the hotspot, a wave sweeps across them, like the iPhone's "searching for network" animation: in Classic each bar grows to its height in the staircase and shrinks back. The animation runs on Core Animation, so it costs no CPU.

## Features

- **Network menu** in the style of the system Wi-Fi menu: a Wi-Fi switch, the current network, *Personal Hotspot* (your iPhone, with its signal and network type the way its status bar shows them; click to turn its hotspot on and join it), *Known Networks*, *Other Networks* (the rest under *More Networks*), and *Ethernet* with the interface and IP address when wired.
- **Join networks** with a click; a password prompt appears for new secured ones. Known networks use the password macOS already has.
- Network names need **Location** access (macOS treats them as location data); the app asks on first launch.
- **Signal bars** (0–4) and **network type** of the iPhone, updated as the iPhone advertises changes.
- **iPhone battery** (optional, off by default): the ring in the iPhone Duo style, or a row of 4 marks under the bars in the Classic style (a full quarter is a segment as wide as its bar, an empty one a small faint dot). Works in both automatic and manual modes. No percentage: the iPhone only advertises its battery in quarters (0, 25, 50, 75, 100).
- **Automatic mode** (default): signal bars always; the network label (5G/LTE) only shows while the Mac is using the iPhone's hotspot.
- **Manual mode**: pick what shows on the hotspot under *Newtray* (signal bars, network type).
- The iPhone's marketing model name (`iPhone18,1` → *iPhone 17 Pro*). The *Newtray* submenu also has **Refresh** (⌘R), and **Quit Newtray** (⌘Q) sits at the bottom.
- **Open at Login** (on by default, toggle in the menu) via `SMAppService`.
- No Dock icon (`LSUIElement`).
- Localized in English and Brazilian Portuguese (String Catalog).

## Requirements

- macOS 27 or later.
- An iPhone with Personal Hotspot, signed in to the same iCloud account, with Bluetooth and Wi-Fi on on the Mac.

## How it works

| Data | Source |
|---|---|
| Network type, signal bars, battery, name and model identifier | `SFRemoteHotspotSession` (Sharing.framework, **private API**), the same source as the macOS Wi-Fi menu |
| Marketing name and model icon | `UTType` with the `com.apple.device-model-code` tag class (UTIs from macOS CoreTypes) |
| Wi-Fi state, nearby networks, joining | CoreWLAN (`CWWiFiClient`, `scanForNetworks`, `associate`) |
| Ethernet and the interface in use | `NWPathMonitor` + `getifaddrs` |
| Turning the iPhone's hotspot on | `SFRemoteHotspotSession enableHotspotForDevice:` (private), which returns the hotspot's network and password |
| Whether the Mac is on the hotspot | `NWPathMonitor.isExpensive` (Network, public API, no Location permission needed) |
| Menu bar item | `NSStatusItem` with the `cellularbars` SF Symbol at 15pt, aligned with the system icons |

`networkType` values sent by the iPhone:

| Value | Network |
|---|---|
| 0 | — |
| 1 | 1x |
| 2 | GPRS |
| 3 | EDGE |
| 4 | 3G |
| 5 | H |
| 6 | 4G |
| 7 | LTE |
| 8 | 5G |

### Limitations

- **Private API**: it can't ship on the Mac App Store and may break with macOS updates.
- **5G SA vs. NSA**: the iPhone only advertises "5G" without telling SA from NSA, so "5G+" can't be shown.
- Updates depend on the iPhone's BLE advertisement; the app restarts the search every 30 seconds to force fresh data.

## Project layout

```
Newtray/
├── NewtrayApp.swift            # App + AppDelegate (no windows)
├── StatusItemController.swift  # NSStatusItem, menu and display options
├── NetworkMonitor.swift        # Wi-Fi (CoreWLAN), Ethernet, Location, scanning and joining
├── NetworkMenuViews.swift      # Custom menu rows (SwiftUI): Wi-Fi switch, network rows, cellular status
├── HotspotDevice+Model.swift   # Marketing name, icon, and the iPhone Duo / Classic glyphs
├── LaunchAtLogin.swift         # Open at Login (SMAppService)
├── SearchAnimationView.swift   # "Searching for network" animation (Core Animation)
├── HotspotMonitor.swift        # SFRemoteHotspotSession + NWPathMonitor
├── Localizable.xcstrings       # String Catalog (en, pt-BR)
└── AppIcon.icon                # App icon (Icon Composer, with dark/clear/tinted variants)
```

## Building

Open `Newtray.xcodeproj` in Xcode and run the **Newtray** scheme, or:

```bash
xcodebuild -project Newtray.xcodeproj -scheme Newtray -configuration Release build
```
