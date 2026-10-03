//
//  NetworkMenuViews.swift
//  Newtray
//
//  Custom rows for the network menu: the Wi-Fi switch and section headers.
//

import SwiftUI

/// Every custom row shares one width so text and trailing icons line up.
let menuRowWidth: CGFloat = 300

/// "Wi-Fi" with an on/off switch, at the top of the menu like the system one.
struct WiFiHeaderView: View {
    let isOn: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Text("Wi-Fi")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 24)
            MenuSwitch(isOn: isOn) { onToggle(!isOn) }
                .accessibilityLabel(Text("Wi-Fi"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(width: menuRowWidth)
    }
}

/// A switch drawn by hand: inside a menu the system one renders as inactive
/// (gray) even when on, unlike the system Wi-Fi menu's blue one.
struct MenuSwitch: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.15))
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.2), value: isOn)
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? Text("On", comment: "Switch state") : Text("Off", comment: "Switch state"))
    }
}

/// A network row like the system Wi-Fi menu's: a round badge with the signal
/// (filled with the accent color for the network in use), the name, and a lock
/// when it needs a password. Highlight and clicks come from MenuRowHostView.
struct NetworkRowView: View {
    let name: String
    /// SF Symbol for the badge, e.g. "wifi" or the Ethernet glyph.
    var symbol = "wifi"
    /// 0–1 for variable symbols like "wifi"; nil for plain ones.
    var level: Double?
    var detail: String?
    var isSecure = false
    var isCurrent = false
    /// Shown at the trailing edge instead of the lock, e.g. the iPhone's signal.
    var accessory: AnyView?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.accentColor : Color.primary.opacity(0.1))
                Group {
                    if let level {
                        Image(systemName: symbol, variableValue: level)
                    } else {
                        Image(systemName: symbol)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 16)
            if let accessory {
                accessory
            } else if isSecure {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Secured", comment: "VoiceOver: the network needs a password"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .frame(width: menuRowWidth, alignment: .leading)
    }
}

/// The iPhone's cellular status the way its own status bar shows it: the signal
/// bars and the network type in bold ("▂▄▆█ 5G"), with the battery marks under
/// the bars when that option is on.
struct CellularStatusView: View {
    let device: HotspotDevice
    let showBattery: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let glyph = device.signalGlyph(pointSize: 14, showBattery: showBattery) {
                Image(nsImage: glyph)
                    .renderingMode(.template)
            }
            Text(device.networkLabel)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(device.networkLabel), \(device.signalBars)/4"))
    }
}
