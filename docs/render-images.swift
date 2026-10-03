// Renders the README images (docs/menu.png, docs/menubar.png, docs/searching.gif)
// with the app's own drawing code and sample data, so they can be regenerated
// after visual changes. From the repository root:
//
//   swiftc -parse-as-library -o /tmp/render-docs Plate/HotspotMonitor.swift \
//     Plate/HotspotDevice+Model.swift Plate/NetworkMenuViews.swift \
//     Plate/MainRunLoop.swift docs/render-images.swift && /tmp/render-docs docs
//
// The icon (docs/icon.png) is exported with Icon Composer's ictool:
//
//   "/Applications/Icon Composer.app/Contents/Executables/ictool" "Plate/Plate Icon.icon" \
//     --export-image --output-file docs/icon.png --platform macOS --rendition Default \
//     --width 256 --height 256 --scale 2

import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main struct Docs { @MainActor static func main() {
  let out = CommandLine.arguments[1]
  let phone = HotspotDevice(id: "1", name: "iPhone", model: "iPhone18,1", networkType: 8, signalBars: 3, batteryLevel: 75)

  // MARK: Menu mock, built from the app's own rows.
  func header(_ t: String) -> some View {
    Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      .frame(width: menuRowWidth, alignment: .leading).padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)
  }
  func item(_ t: String, trailing: String? = nil, chevron: Bool = false) -> some View {
    HStack { Text(t).font(.system(size: 13)); Spacer()
      if let trailing { Text(trailing).font(.system(size: 13)).foregroundStyle(.tertiary) }
      if chevron { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) } }
      .padding(.horizontal, 14).padding(.vertical, 3).frame(width: menuRowWidth)
  }
  func divider() -> some View { Divider().padding(.horizontal, 14).padding(.vertical, 5).frame(width: menuRowWidth) }

  func menu(_ scheme: ColorScheme) -> some View {
    VStack(spacing: 0) {
      WiFiHeaderView(isOn: true) { _ in }
      NetworkRowView(name: "Home", level: 1, isCurrent: true)
      header("Personal Hotspot")
      NetworkRowView(name: "iPhone", symbol: "personalhotspot", detail: "iPhone 17 Pro",
                     accessory: AnyView(CellularStatusView(device: phone, showBattery: false)))
      header("Known Networks")
      NetworkRowView(name: "Office", level: 2.0 / 3, isSecure: true)
      header("Other Networks")
      NetworkRowView(name: "Café Guest", level: 2.0 / 3)
      NetworkRowView(name: "Studio 5G", level: 2.0 / 3, isSecure: true)
      NetworkRowView(name: "Library", level: 1.0 / 3, isSecure: true)
      divider()
      item("Network Settings…")
      divider()
      item("Plate", chevron: true)
      item("Quit Plate", trailing: "⌘Q")
    }
    .padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
      .shadow(color: .black.opacity(0.25), radius: 14, y: 6))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    .padding(24)
    .environment(\.colorScheme, scheme)
  }
  let menus = HStack(spacing: 0) { menu(.light); menu(.dark) }.background(Color(white: 0.5).opacity(0.0001))
  let r = ImageRenderer(content: menus); r.scale = 2
  write(r.cgImage!, "\(out)/menu.png")

  // MARK: Menu bar states.
  let thickness: CGFloat = 22
  let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
  let wifi = NSImage(systemSymbolName: "wifi", variableValue: 1, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
  let tower = phone.signalGlyph(pointSize: 15, showBattery: false, canvasHeight: thickness, verticalOffset: 0.5)!
  let towerBattery = phone.signalGlyph(pointSize: 15, showBattery: true, canvasHeight: thickness, verticalOffset: 0.5)!
  struct State { let caption: String; let draw: (NSPoint, NSColor) -> CGFloat }
  func drawTemplate(_ img: NSImage, at p: NSPoint, _ color: NSColor, dy: CGFloat = 0) -> CGFloat {
    NSImage(size: img.size, flipped: false) { r in img.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
      .draw(in: NSRect(x: p.x, y: p.y + dy, width: img.size.width, height: img.size.height)); return img.size.width
  }
  let states: [State] = [
    State(caption: "iPhone Duo · Wi-Fi") { p, c in drawTemplate(phone.duoConnectionGlyph(center: ("wifi", 1), pointSize: 13.5, showBattery: true, canvasHeight: thickness)!, at: p, c) },
    State(caption: "iPhone Duo · on the hotspot") { p, c in drawTemplate(phone.duoGlyph(size: 19, showBattery: true, showNetwork: true, canvasHeight: thickness), at: p, c) },
    State(caption: "Classic · Wi-Fi") { p, c in
      var w = drawTemplate(tower, at: p, c); w += 17
      w += drawTemplate(wifi, at: NSPoint(x: p.x + w, y: p.y), c, dy: (thickness - wifi.size.height) / 2 + 1); return w },
    State(caption: "Classic · on the hotspot") { p, c in
      var w = drawTemplate(towerBattery, at: p, c) + 6
      let t = NSAttributedString(string: "5G", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: c])
      t.draw(at: NSPoint(x: p.x + w, y: p.y + 3.5)); w += t.size().width; return w },
  ]
  let cell: CGFloat = 170, W = cell * CGFloat(states.count), H: CGFloat = 2 * 30 + 26
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 3), pixelsHigh: Int(H * 3), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: W, height: H)
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  for (row, (bg, fg)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.13, alpha: 1), NSColor.white)].enumerated() {
    let y = H - 30 * CGFloat(row + 1)
    bg.setFill(); NSRect(x: 0, y: y, width: W, height: 30).fill()
    for (i, s) in states.enumerated() {
      // Measure, then center the glyph in its cell.
      let probe = NSImage(size: NSSize(width: 200, height: thickness)); probe.lockFocus(); let w = s.draw(.zero, .clear); probe.unlockFocus()
      _ = s.draw(NSPoint(x: CGFloat(i) * cell + (cell - w) / 2, y: y + 4), fg)
    }
  }
  let cap: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5, weight: .medium), .foregroundColor: NSColor(white: 0.5, alpha: 1)]
  for (i, s) in states.enumerated() {
    let t = NSAttributedString(string: s.caption, attributes: cap)
    t.draw(at: NSPoint(x: CGFloat(i) * cell + (cell - t.size().width) / 2, y: 7))
  }
  NSGraphicsContext.current = nil
  write(rep.cgImage!, "\(out)/menubar.png")

  // MARK: Searching animation GIF (Classic bars + Duo dots), on a dark menu bar.
  let none = HotspotDevice(id: "", name: "", model: "", networkType: 0, signalBars: 0, batteryLevel: 0)
  let fps = 30.0, cycle = 1.6, frames = Int(fps * cycle)
  let gifURL = URL(fileURLWithPath: "\(out)/searching.gif")
  let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames, nil)!
  CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
  for f in 0..<frames {
    let phase = CGFloat(Double(f) / Double(frames))
    let gw: CGFloat = 110, gh: CGFloat = 30
    let g = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(gw * 3), pixelsHigh: Int(gh * 3), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    g.size = NSSize(width: gw, height: gh)
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: g)
    NSColor(white: 0.13, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: gw, height: gh).fill()
    _ = drawTemplate(none.signalGlyph(pointSize: 15, showBattery: false, canvasHeight: thickness, verticalOffset: 0.5, searchPhase: phase)!, at: NSPoint(x: 18, y: 4), .white)
    _ = drawTemplate(none.duoGlyph(size: 19, showBattery: false, showNetwork: false, canvasHeight: thickness, isPlaceholder: true, searchPhase: phase), at: NSPoint(x: 70, y: 4), .white)
    NSGraphicsContext.current = nil
    CGImageDestinationAddImage(dest, g.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
  }
  CGImageDestinationFinalize(dest)
}}

func write(_ image: CGImage, _ path: String) {
  try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
