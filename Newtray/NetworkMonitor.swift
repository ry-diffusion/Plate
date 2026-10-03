//
//  NetworkMonitor.swift
//  Newtray
//
//  Wi-Fi and Ethernet state for the menu: which interface is carrying traffic,
//  the current Wi-Fi network and signal, nearby networks and joining them.
//
//  Wi-Fi network names (SSIDs) are location data on macOS, so they're only
//  readable once the user grants Location access.
//

import CoreLocation
import CoreWLAN
import Darwin
import Network
import Observation

/// A nearby Wi-Fi network from a scan, one per name (the strongest BSS).
struct WiFiNetwork: Identifiable, Equatable {
    var id: String { ssid }
    let ssid: String
    /// RSSI in dBm.
    let rssi: Int
    let isSecure: Bool
    let isKnown: Bool
    /// What CoreWLAN needs to join it.
    let network: CWNetwork

    /// Wi-Fi signal as 1–3 arcs, like the system menu.
    var bars: Int { WiFiNetwork.bars(rssi: rssi) }

    static func bars(rssi: Int) -> Int {
        if rssi >= -60 { return 3 }
        if rssi >= -72 { return 2 }
        return 1
    }

    static func == (lhs: WiFiNetwork, rhs: WiFiNetwork) -> Bool {
        lhs.ssid == rhs.ssid && lhs.rssi == rhs.rssi && lhs.isSecure == rhs.isSecure && lhs.isKnown == rhs.isKnown
    }
}

@Observable
final class NetworkMonitor: NSObject {
    /// The interface currently carrying traffic.
    enum Connection: Equatable {
        case wifi, ethernet, other, none
    }

    private(set) var connection: Connection = .none
    /// BSD name and IPv4 address of the interface carrying traffic.
    private(set) var primaryInterface: String?
    private(set) var primaryAddress: String?

    private(set) var wifiPowerOn = false
    private(set) var currentSSID: String?
    private(set) var wifiRSSI = 0
    /// Associated to a network, whether or not the name is readable.
    private(set) var isWiFiAssociated = false

    private(set) var networks: [WiFiNetwork] = []
    private(set) var isScanning = false
    private(set) var locationStatus: CLAuthorizationStatus = .notDetermined

    var hasLocationAccess: Bool {
        locationStatus == .authorizedAlways || locationStatus == .authorized
    }

    private let client = CWWiFiClient.shared()
    private let pathMonitor = NWPathMonitor()
    private let locationManager = CLLocationManager()
    private var lastScan: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        locationStatus = locationManager.authorizationStatus
        // Network names are the core of the menu, so ask right away the first time.
        if locationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        client.delegate = self
        for event: CWEventType in [.powerDidChange, .ssidDidChange, .linkDidChange, .linkQualityDidChange] {
            try? client.startMonitoringEvent(with: event)
        }
        refreshWiFi()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connection: Connection
            if path.status != .satisfied {
                connection = .none
            } else if path.usesInterfaceType(.wiredEthernet) {
                connection = .ethernet
            } else if path.usesInterfaceType(.wifi) {
                connection = .wifi
            } else {
                connection = .other
            }
            // The first available interface is the one the path prefers.
            let name = path.availableInterfaces.first { $0.type != .other }?.name
            onMainRunLoop { [weak self] in
                guard let self else { return }
                self.connection = connection
                self.primaryInterface = name
                self.primaryAddress = name.flatMap(Self.ipv4Address(of:))
                self.refreshWiFi()
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    // MARK: - Location

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Wi-Fi

    func refreshWiFi() {
        let interface = client.interface()
        wifiPowerOn = interface?.powerOn() ?? false
        currentSSID = interface?.ssid()
        wifiRSSI = interface?.rssiValue() ?? 0
        // The SSID needs Location; the channel doesn't, so it tells "associated" either way.
        isWiFiAssociated = interface?.wlanChannel() != nil
    }

    func setWiFiPower(_ on: Bool) {
        try? client.interface()?.setPower(on)
        refreshWiFi()
        if on { scan(force: true) } else { networks = [] }
    }

    /// Scans in the background. Skips if the last scan is recent, since a scan
    /// takes a few seconds and briefly disturbs the link.
    func scan(force: Bool = false) {
        guard wifiPowerOn, !isScanning else { return }
        if !force, let lastScan, Date().timeIntervalSince(lastScan) < 10 { return }
        guard let interface = client.interface() else { return }
        isScanning = true
        let known = Set(interface.configuration()?.networkProfiles.array
            .compactMap { ($0 as? CWNetworkProfile)?.ssid } ?? [])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = (try? interface.scanForNetworks(withName: nil)) ?? []
            // One entry per name, keeping the strongest access point.
            var best: [String: CWNetwork] = [:]
            for network in found {
                guard let ssid = network.ssid, !ssid.isEmpty else { continue }
                if let current = best[ssid], current.rssiValue >= network.rssiValue { continue }
                best[ssid] = network
            }
            let networks = best.map { ssid, network in
                WiFiNetwork(ssid: ssid, rssi: network.rssiValue, isSecure: !network.supportsSecurity(.none),
                            isKnown: known.contains(ssid), network: network)
            }
            .sorted { $0.rssi > $1.rssi }

            onMainRunLoop { [weak self] in
                guard let self else { return }
                self.networks = networks
                self.isScanning = false
                self.lastScan = .now
            }
        }
    }

    /// Joins `network`. A nil password works for open networks and for known
    /// ones, whose password macOS already has in the keychain.
    func join(_ network: WiFiNetwork, password: String?) async throws {
        guard let interface = client.interface() else { return }
        let target = network.network
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try interface.associate(to: target, password: password)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        refreshWiFi()
    }

    /// Joins the network named `ssid` (scanning for it first), e.g. the iPhone's
    /// hotspot right after it's been turned on.
    func join(ssid: String, password: String?) async throws {
        guard let interface = client.interface() else { return }
        let found: Set<CWNetwork> = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try interface.scanForNetworks(withName: ssid))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        guard let target = found.max(by: { $0.rssiValue < $1.rssiValue }) else {
            // kCWTimeoutErr: the network never showed up in the scan.
            throw NSError(domain: CWErrorDomain, code: -3905)
        }
        let network = WiFiNetwork(ssid: ssid, rssi: target.rssiValue, isSecure: !target.supportsSecurity(.none),
                                  isKnown: false, network: target)
        try await join(network, password: password)
    }

    // MARK: - Helpers

    private static func ipv4Address(of interface: String) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard String(cString: entry.ifa_name) == interface,
                  let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}

extension NetworkMonitor: CWEventDelegate {
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { refreshSoon() }
    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) { refreshSoon() }
    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) { refreshSoon() }
    nonisolated func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) {
        refreshSoon()
    }

    /// CoreWLAN calls the delegate on its own queue.
    nonisolated private func refreshSoon() {
        onMainRunLoop { self.refreshWiFi() }
    }
}

extension NetworkMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        onMainRunLoop {
            self.locationStatus = status
            self.refreshWiFi()
            self.scan(force: true)
        }
    }
}
