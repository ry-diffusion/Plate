//
//  DeviceHeaderView.swift
//  Newtray
//
//  Menu header for an iPhone: icon, name, model, network and battery.
//

import SwiftUI

struct DeviceHeaderView: View {
    let device: HotspotDevice
    var showBattery = true

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: device.modelIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(device.modelName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            // Same drawing as the menu bar: signal (with the battery below) and network.
            HStack(spacing: 6) {
                if let glyph = device.signalGlyph(pointSize: 15, showBattery: showBattery) {
                    Image(nsImage: glyph)
                        .renderingMode(.template)
                }
                Text(device.networkLabel)
                    .fontWeight(.bold)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minWidth: 260)
    }
}
