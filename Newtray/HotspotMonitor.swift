//
//  HotspotMonitor.swift
//  Newtray
//
//  Lê os dados do Instant Hotspot (tipo de rede celular, barras de sinal e bateria) do iPhone
//  através da API privada SFRemoteHotspotSession (Sharing.framework), a mesma
//  fonte que o menu de Wi-Fi do macOS usa.
//

import Foundation
import Network
import Observation

struct HotspotDevice: Equatable, Identifiable {
    let id: String
    let name: String
    let model: String
    let networkType: Int
    /// Barras de sinal, 0–4.
    let signalBars: Int
    /// Bateria do iPhone em %, 0–100.
    let batteryLevel: Int

    /// Rótulos tirados de -[SFRemoteHotspotDevice description].
    var networkLabel: String {
        switch networkType {
        case 1: "1x"
        case 2: "GPRS"
        case 3: "EDGE"
        case 4: "3G"
        case 5: "H"
        case 6: "4G"
        case 7: "LTE"
        case 8: "5G"
        default: "—"
        }
    }
}

@Observable
final class HotspotMonitor {
    private(set) var devices: [HotspotDevice] = []
    private(set) var lastUpdate: Date?
    private(set) var isAvailable = true
    /// Se o Mac está saindo pra internet pelo hotspot do iPhone. O macOS marca
    /// o Personal Hotspot como conexão cara (`isExpensive`), sem pedir
    /// permissão de Localização como o SSID pediria.
    private(set) var isUsingHotspot = false

    /// O primeiro device encontrado (normalmente só existe um iPhone).
    var device: HotspotDevice? { devices.first }

    private var session: NSObject?
    private let delegate = SessionDelegate()
    private var refreshTimer: Timer?
    private let pathMonitor = NWPathMonitor()

    init() {
        delegate.onUpdate = { [weak self] devices in
            self?.devices = devices
            self?.lastUpdate = .now
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let usingHotspot = path.status == .satisfied && path.isExpensive
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.isUsingHotspot = usingHotspot }
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        start()
    }

    func start() {
        guard session == nil else { return }
        guard dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY) != nil,
              let cls = NSClassFromString("SFRemoteHotspotSession") as? NSObject.Type else {
            isAvailable = false
            return
        }
        let session = cls.init()
        session.setValue(delegate, forKey: "delegate")
        session.perform(NSSelectorFromString("startBrowsing"))
        self.session = session

        // O sharingd só avisa quando o anúncio BLE do iPhone muda; reiniciar o
        // browse de tempos em tempos força uma lista nova.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartBrowsing() }
        }
    }

    func restartBrowsing() {
        session?.perform(NSSelectorFromString("stopBrowsing"))
        session?.perform(NSSelectorFromString("startBrowsing"))
    }
}

private final class SessionDelegate: NSObject {
    var onUpdate: (([HotspotDevice]) -> Void)?

    /// Chamado pelo SFRemoteHotspotSession numa fila de XPC.
    @objc(session:updatedFoundDevices:)
    nonisolated func session(_ session: AnyObject, updatedFoundDevices devices: NSArray) {
        let parsed = devices.compactMap { ($0 as? NSObject).flatMap(HotspotDevice.init(sharingDevice:)) }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onUpdate?(parsed) }
        }
    }
}

private extension HotspotDevice {
    nonisolated init?(sharingDevice d: NSObject) {
        guard let id = d.value(forKey: "deviceIdentifier") as? String else { return nil }
        self.init(
            id: id,
            name: d.value(forKey: "deviceName") as? String ?? "iPhone",
            model: d.value(forKey: "model") as? String ?? "",
            networkType: (d.value(forKey: "networkType") as? NSNumber)?.intValue ?? 0,
            signalBars: (d.value(forKey: "signalStrength") as? NSNumber)?.intValue ?? 0,
            batteryLevel: (d.value(forKey: "batteryLife") as? NSNumber)?.intValue ?? 0
        )
    }
}
