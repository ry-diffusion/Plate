<p align="center">
  <img src="docs/icon.png" width="128" alt="Plate icon">
</p>

<h1 align="center">Plate</h1>

<p align="center">
  <b>Your Wi-Fi and your iPhone's signal, side by side in the menu bar.</b><br>
  A friendlier Wi-Fi menu for your Mac that also shows how your iPhone's hotspot is doing (5G or LTE, signal and battery) without opening anything.
</p>

<p align="center">
  <img src="docs/menu.png" width="720" alt="The Plate menu in light and dark mode: Wi-Fi switch, current network, the iPhone under Personal Hotspot with its signal and 5G, known and other networks">
</p>

## Why Plate?

If you tether to your iPhone, you know the drill: open the Wi-Fi menu just to check whether you're on 5G or how many bars you have. Plate puts that right in the menu bar, next to your Wi-Fi, and gives you a cleaner menu to switch networks.

- 📶 **See your iPhone's signal at a glance**, plus 5G/LTE/4G when you're on its hotspot.
- 🔋 **Keep an eye on your iPhone's battery** (optional).
- 🛜 **Switch Wi-Fi networks** with one click, just like the system menu.
- 📱 **Turn on your iPhone's hotspot from your Mac**: click your iPhone and Plate connects for you.
- 🔌 **Ethernet aware**: shows when you're plugged in, with your IP address.
- 🌗 Looks at home in light and dark mode, in English and Brazilian Portuguese.

## Two looks to choose from

<p align="center">
  <img src="docs/menubar.png" width="820" alt="Menu bar item in the iPhone Duo and Classic styles, on Wi-Fi and on the iPhone's hotspot, over light and dark menu bars">
</p>

- **iPhone Duo** (default) borrows the round status icon from iPhone Duo: your Wi-Fi in the middle, your iPhone's signal as the little dots below, and its battery as the ring around it. On the hotspot, the middle shows 5G or LTE instead.
- **Classic** shows your iPhone's signal bars next to the Wi-Fi icon, like two separate menu bar icons. On the hotspot you see the bars with "5G" beside them.

Switch between them under **Plate › Menu Bar Style**.

<p align="center">
  <img src="docs/searching.gif" width="220" alt="Searching animation: a wave across short bars in Classic and across the dots in iPhone Duo">
</p>

No iPhone around? Plate shows short, faint bars, just like an iPhone with no service. And if you're on the hotspot while your iPhone is out of reach, it plays the same "searching for network" wave your iPhone does.

## Getting started

1. **Install**: Plate isn't on the App Store yet (see the FAQ), so build it with Xcode: open `Plate.xcodeproj`, choose the **Plate** scheme and press **Run** (⌘R). For a copy to keep, use **Product › Archive** and drag `Plate.app` to your Applications folder.
2. **Allow Location** when macOS asks. It's only used to show the names of nearby Wi-Fi networks (see the FAQ for why).
3. **Look for Plate in the menu bar.** It opens at login from now on; you can turn that off under **Plate › Open at Login**.

**Tip:** to let Plate fully replace the system Wi-Fi icon, go to **System Settings › Control Center › Wi-Fi** and choose **Don't Show in Menu Bar**.

## Using Plate

- **Join a network**: click it. Networks you've used before connect right away; new ones with a 🔒 ask for the password.
- **Use your iPhone's hotspot**: click your iPhone under **Personal Hotspot**. Plate turns the hotspot on and connects.
- **Turn Wi-Fi off or on** with the switch at the top.
- **Show your iPhone's battery**: open the **Plate** menu and tick **iPhone Battery**.
- **Choose what shows while on the hotspot**: in the **Plate** menu, under **On the Hotspot** (Automatic is a good default).

## FAQ

**Why does Plate ask for my location?**
macOS treats the names of nearby Wi-Fi networks as location data, so any app that lists them needs Location access. Plate never looks up where you are; it only reads network names, and nothing leaves your Mac.

**My iPhone's battery always seems to be at 75% or 100%.**
Your iPhone only shares its battery in quarters (25, 50, 75, 100%), so Plate shows it as a level rather than an exact percentage.

**Can Plate tell 5G from 5G+ (standalone)?**
Not yet: your iPhone just says "5G", without the detail.

**My iPhone doesn't show up.**
Make sure Personal Hotspot is set up on the iPhone, both devices use the same Apple Account, and Bluetooth and Wi-Fi are on on your Mac. Plate refreshes every 30 seconds; you can also use **Plate › Refresh** (⌘R).

**Why isn't it on the App Store?**
Plate reads your iPhone's hotspot details the same way the macOS Wi-Fi menu does, through an Apple framework that apps on the App Store aren't allowed to use. That also means a future macOS update could break it.

## Requirements

- macOS 27 or later
- An iPhone with Personal Hotspot, signed in to the same Apple Account

<details>
<summary><b>For developers</b></summary>

### How it works

| What | Where it comes from |
|---|---|
| iPhone's network type, signal, battery and model | `SFRemoteHotspotSession` in Sharing.framework (**private API**), the same source as the macOS Wi-Fi menu |
| Turning the iPhone's hotspot on | `SFRemoteHotspotSession enableHotspotForDevice:` (private), which returns the hotspot's network and password, joined with CoreWLAN |
| Marketing name and icon of the iPhone model | `UTType` with the `com.apple.device-model-code` tag class |
| Wi-Fi state, nearby networks, joining | CoreWLAN (`CWWiFiClient`, `scanForNetworks`, `associate`) |
| Ethernet and the interface in use | `NWPathMonitor` + `getifaddrs` |
| Whether the Mac is on the hotspot | `NWPathMonitor.isExpensive` |
| Searching animation | Core Animation over the static glyph, so it costs no CPU |

`networkType` values sent by the iPhone: 0 none, 1 1x, 2 GPRS, 3 EDGE, 4 3G, 5 H, 6 4G, 7 LTE, 8 5G.

The iPhone only reports when its Bluetooth advertisement changes, so Plate restarts the search every 30 seconds. Menu updates are delivered in the run loop's common modes, since an open menu doesn't get `DispatchQueue.main` work until it closes.

### Project layout

```
Plate/
├── PlateApp.swift              # App + AppDelegate (no windows)
├── StatusItemController.swift  # Menu bar item, menu and options
├── NetworkMonitor.swift        # Wi-Fi (CoreWLAN), Ethernet, Location, scanning and joining
├── HotspotMonitor.swift        # iPhone hotspot data (Sharing.framework)
├── HotspotDevice+Model.swift   # Model names and the iPhone Duo / Classic glyphs
├── NetworkMenuViews.swift      # Custom menu rows (SwiftUI)
├── MenuRowHostView.swift       # Native menu highlight for the custom rows
├── SearchAnimationView.swift   # "Searching for network" animation
├── LaunchAtLogin.swift         # Open at Login (SMAppService)
├── MainRunLoop.swift           # Main-thread delivery that works while a menu is open
├── Localizable.xcstrings       # English and Brazilian Portuguese
└── Plate Icon.icon             # App icon (Icon Composer)
docs/                           # README images and the script that renders them
```

### Building

```bash
xcodebuild -project Plate.xcodeproj -scheme Plate -configuration Release build
```

The README images are rendered with the app's own drawing code; see `docs/render-images.swift` to regenerate them.

</details>
