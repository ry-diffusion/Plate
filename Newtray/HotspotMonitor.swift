//
//  HotspotMonitor.swift
//  Newtray
//
//  Reads the iPhone's Instant Hotspot data (cellular network type, signal bars
//  and battery) through the private SFRemoteHotspotSession API
//  (Sharing.framework), the same source the macOS Wi-Fi menu uses.
//

import Foundation
import Network
import Observation

struct HotspotDevice: Equatable, Identifiable {
    let id: String
    let name: String
    let model: String
    let networkType: Int
    /// Signal bars, 0–4.
    let signalBars: Int
    /// iPhone battery in %, 0–100.
    let batteryLevel: Int

    /// Labels taken from -[SFRemoteHotspotDevice description].
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
    /// Whether the Mac is reaching the internet through the iPhone's hotspot.
    /// macOS flags Personal Hotspot as an expensive connection (`isExpensive`),
    /// which needs no Location permission, unlike reading the SSID.
    private(set) var isUsingHotspot = false

    /// The first device found (there's usually only one iPhone).
    var device: HotspotDevice? { devices.first }

    private var session: NSObject?
    /// The SFRemoteHotspotDevice behind each device, needed to turn its hotspot on.
    private var sharingDevices: [String: NSObject] = [:]
    private let delegate = SessionDelegate()
    private var refreshTimer: Timer?
    private let pathMonitor = NWPathMonitor()

    init() {
        delegate.onUpdate = { [weak self] found in
            self?.devices = found.map(\.device)
            self?.sharingDevices = Dictionary(found.map { ($0.device.id, $0.object) }, uniquingKeysWith: { a, _ in a })
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

        // sharingd only reports when the iPhone's BLE advertisement changes;
        // restarting the browse every so often forces a fresh list.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartBrowsing() }
        }
    }

    func restartBrowsing() {
        session?.perform(NSSelectorFromString("stopBrowsing"))
        session?.perform(NSSelectorFromString("startBrowsing"))
    }

    /// The Wi-Fi network the iPhone's hotspot broadcasts once it's on.
    struct HotspotCredentials {
        let ssid: String
        let password: String?
    }

    /// Asks the iPhone to turn its Personal Hotspot on, the way the Wi-Fi menu
    /// does, and returns the network to join.
    func enableHotspot(on device: HotspotDevice) async throws -> HotspotCredentials {
        guard let session, let target = sharingDevices[device.id] else {
            throw NSError(domain: "Newtray", code: 1)
        }
        let selector = NSSelectorFromString("enableHotspotForDevice:withCompletionHandler:")
        return try await withCheckedThrowingContinuation { continuation in
            // -enableHotspotForDevice:withCompletionHandler: replies with an
            // SFRemoteHotspotInfo (name, password, channel) or an error.
            let completion: @convention(block) (AnyObject?, NSError?) -> Void = { info, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let info = info as? NSObject, let ssid = info.value(forKey: "name") as? String {
                    continuation.resume(returning: HotspotCredentials(ssid: ssid, password: info.value(forKey: "password") as? String))
                } else {
                    continuation.resume(throwing: NSError(domain: "Newtray", code: 2))
                }
            }
            session.perform(selector, with: target, with: completion)
        }
    }
}

private final class SessionDelegate: NSObject {
    var onUpdate: (([(device: HotspotDevice, object: NSObject)]) -> Void)?

    /// Called by SFRemoteHotspotSession on an XPC queue.
    @objc(session:updatedFoundDevices:)
    nonisolated func session(_ session: AnyObject, updatedFoundDevices devices: NSArray) {
        let parsed = devices.compactMap { item -> (device: HotspotDevice, object: NSObject)? in
            guard let object = item as? NSObject, let device = HotspotDevice(sharingDevice: object) else { return nil }
            return (device, object)
        }
        nonisolated(unsafe) let found = parsed
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onUpdate?(found) }
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
