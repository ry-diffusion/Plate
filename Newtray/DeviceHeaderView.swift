//
//  DeviceHeaderView.swift
//  Newtray
//
//  Cabeçalho do menu com o iPhone: ícone, nome, modelo, rede e bateria.
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

            // Mesmo desenho da status bar: torre (com a bateria embaixo) e rede.
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
