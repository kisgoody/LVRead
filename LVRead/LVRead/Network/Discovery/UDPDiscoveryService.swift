import Foundation
import Network
import UIKit

// MARK: - UDP Discovery Service

/// Handles UDP broadcasting and listening for device discovery on the local network.
/// Sends periodic heartbeats and maintains a dictionary of discovered LanDevice instances.
final class UDPDiscoveryService {

    public static let shared = UDPDiscoveryService()

    private let discoveryPort: UInt16 = 29876
    private let broadcastHost: String = "255.255.255.255"

    private var listener: NWListener?
    private var heartbeatTimer: Timer?
    private var isRunning = false

    /// Unique identifier for this device, generated once per install / session.
    public let deviceId: String

    /// The device name broadcast to peers.
    public var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "LVRead_deviceName") }
    }

    /// Dictionary of discovered devices keyed by deviceId.
    private var discoveredDevices: [String: LanDevice] = [:]
    private let deviceLock = NSLock()

    /// Callback invoked when a new device is discovered or refreshed.
    public var onDeviceDiscovered: ((LanDevice) -> Void)?

    /// Callback invoked when a device is marked offline.
    public var onDeviceOffline: ((LanDevice) -> Void)?

    // MARK: - Initialization

    private init() {
        self.deviceId = UDPDiscoveryService.loadOrCreateDeviceId()
        self.deviceName = UserDefaults.standard.string(forKey: "LVRead_deviceName")
            ?? UIDevice.current.name
    }

    // MARK: - Public API

    /// Starts discovery: begins listening for broadcasts and sends heartbeats.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        do {
            try startListening()
        } catch {
            print(" Failed to start listener: \(error)")
            isRunning = false
            return
        }

        // Send an immediate heartbeat, then every 3 seconds.
        sendHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    /// Stops discovery: tears down the listener and heartbeat timer.
    public func stop() {
        isRunning = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        listener?.cancel()
        listener = nil
        deviceLock.lock()
        discoveredDevices.removeAll()
        deviceLock.unlock()
    }

    /// Returns a snapshot of currently discovered devices.
    public func getDiscoveredDevices() -> [LanDevice] {
        deviceLock.lock()
        defer { deviceLock.unlock() }
        return Array(discoveredDevices.values)
    }

    /// Returns the local IP address of the en0 (Wi-Fi) interface, or en1 if unavailable.
    public func getLocalIP() -> String? {
        var address: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                                socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                socklen_t(0),
                                NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        freeifaddrs(ifaddr)

        // Fallback to en1 if en0 not found
        if address == nil {
            address = getLocalIPFallback()
        }

        return address
    }

    // MARK: - Private: Listening

    private func startListening() throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: discoveryPort) else {
            throw NSError(domain: "UDPDiscoveryService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        listener = try NWListener(using: params, on: port)

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print(" Listener ready on port \(self.discoveryPort)")
            case .failed(let error):
                print(" Listener failed: \(error)")
            case .cancelled:
                print(" Listener cancelled")
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .background))
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .background))
        receiveOn(connection)
    }

    private func receiveOn(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let error = error {
                print(" Receive error: \(error)")
                connection.cancel()
                return
            }

            if let data = data {
                self?.processDatagram(data: data, connection: connection)
            }

            // Continue listening on this connection
            if self?.isRunning == true {
                self?.receiveOn(connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func processDatagram(data: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        guard type == "LVREAD_DISCOVERY" || type == "LVREAD_ONLINE" else {
            return
        }

        guard let senderDeviceId = json["deviceId"] as? String,
              senderDeviceId != self.deviceId else {
            return
        }

        // Extract sender IP from connection endpoint
        let senderIP = extractIP(from: connection)

        let senderPort: UInt16
        if let port = json["port"] as? UInt16 {
            senderPort = port
        } else if let portNum = json["port"] as? Int {
            senderPort = UInt16(portNum)
        } else {
            senderPort = 29877
        }

        let device = LanDevice(
            id: senderDeviceId,
            deviceName: (json["deviceName"] as? String) ?? "Unknown",
            deviceModel: (json["deviceModel"] as? String) ?? UIDevice.current.model,
            platform: "iOS",
            ipAddress: senderIP,
            port: Int(senderPort),
            lastSeenTimestamp: Date(),
            isOnline: true
        )

        deviceLock.lock()
        discoveredDevices[senderDeviceId] = device
        deviceLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onDeviceDiscovered?(device)
        }
    }

    // MARK: - Private: Heartbeat

    private func sendHeartbeat() {
        guard let localIP = getLocalIP() else { return }

        let message: [String: Any] = [
            "type": "LVREAD_DISCOVERY",
            "deviceId": deviceId,
            "deviceName": deviceName,
            "deviceModel": UIDevice.current.model,
            "platform": "iOS",
            "port": 29877
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        guard let broadcastPort = NWEndpoint.Port(rawValue: discoveryPort) else { return }

        // Broadcast using 255.255.255.255
        let connection = NWConnection(
            host: NWEndpoint.Host(broadcastHost),
            port: broadcastPort,
            using: params
        )

        connection.start(queue: .global(qos: .background))
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print(" Heartbeat send error: \(error)")
            }
            connection.cancel()
        })
    }

    // MARK: - Private Helpers

    private func extractIP(from connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let ipv4):
                return ipv4.debugDescription
            case .name(let name, _):
                return name
            default:
                return "0.0.0.0"
            }
        default:
            return "0.0.0.0"
        }
    }

    private func getLocalIPFallback() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) && name == "en1" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST)
                address = String(cString: hostname)
                break
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Persistence

    private static func loadOrCreateDeviceId() -> String {
        let key = "LVRead_deviceId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Offline Detection (simple timeout)

    /// Marks devices that haven't been seen within `timeout` seconds as offline.
    public func purgeStaleDevices(olderThan timeout: TimeInterval = 15.0) {
        let cutoff = Date().addingTimeInterval(-timeout)
        deviceLock.lock()
        var offlineDevices: [LanDevice] = []
        for (key, device) in discoveredDevices {
            if device.lastSeenTimestamp < cutoff {
                discoveredDevices.removeValue(forKey: key)
                offlineDevices.append(device)
            }
        }
        deviceLock.unlock()

        for device in offlineDevices {
            var offline = device
            offline.isOnline = false
            DispatchQueue.main.async { [weak self] in
                self?.onDeviceOffline?(offline)
            }
        }
    }
}
