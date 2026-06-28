import Foundation
import Network

/// Discovers AudioRelay servers on the local network using:
/// 1. Bonjour/mDNS service discovery
/// 2. UDP broadcast probe (compatible with AudioRelay's broadcast mechanism)
final class ServerDiscoverer: Sendable {
    typealias DiscoveryHandler = @Sendable (ServerInfo) -> Void

    private let onDiscover: DiscoveryHandler
    private var browser: NWBrowser?
    private var broadcastConnection: NWConnection?
    private var isRunning = false
    private var discoveredIds = Set<String>()

    private let bonjourService = "_audiorelay._tcp"
    private let broadcastPort: UInt16 = 59200

    init(onDiscover: @escaping DiscoveryHandler) {
        self.onDiscover = onDiscover
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        startBonjourBrowsing()
        sendBroadcastProbe()

        // Periodic broadcast probe
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendBroadcastProbe()
        }
    }

    func stop() {
        isRunning = false
        browser?.cancel()
        browser = nil
        broadcastConnection?.cancel()
        broadcastConnection = nil
    }

    // MARK: - Bonjour/mDNS Discovery

    private func startBonjourBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: bonjourService, domain: "local."),
            using: params
        )

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                self?.resolveBonjourResult(result)
            }
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("[Discovery] Bonjour browser failed: \(error)")
            default:
                break
            }
        }

        browser?.start(queue: .global(qos: .background))
    }

    private func resolveBonjourResult(_ result: NWBrowser.Result) {
        let endpoint = result.endpoint

        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                    self?.addDiscoveredServer(host: host.debugDescription, port: port.rawValue)
                }
                connection.cancel()
            case .failed:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .background))
    }

    // MARK: - UDP Broadcast Probe

    /// Sends a broadcast probe to discover AudioRelay servers on the LAN.
    /// AudioRelay servers listen on port 59200 and respond to discovery probes.
    private func sendBroadcastProbe() {
        // Get broadcast address
        let broadcastHost = getBroadcastAddress() ?? "255.255.255.255"

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(broadcastHost),
            port: NWEndpoint.Port(integerLiteral: broadcastPort)
        )

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.any),
            port: .any
        )

        broadcastConnection = NWConnection(to: endpoint, using: params)

        broadcastConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Send a simple discovery probe
                let probe = "AudioRelay Discover".data(using: .utf8)!
                self?.broadcastConnection?.send(content: probe, completion: .contentProcessed { _ in })

                // Listen for response
                self?.receiveBroadcastResponse()

            case .failed(let error):
                print("[Discovery] Broadcast failed: \(error)")
            default:
                break
            }
        }

        broadcastConnection?.start(queue: .global(qos: .background))

        // Cleanup after timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.broadcastConnection?.cancel()
        }
    }

    private func receiveBroadcastResponse() {
        broadcastConnection?.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, let data = data else { return }

            // Try to parse server info from response
            if let serverInfo = self.parseDiscoveryResponse(data) {
                self.addDiscoveredServer(
                    host: serverInfo.host,
                    port: serverInfo.port,
                    audioPort: serverInfo.audioPort,
                    name: serverInfo.name
                )
            }

            // Continue listening for more responses
            self.receiveBroadcastResponse()
        }
    }

    private func parseDiscoveryResponse(_ data: Data) -> (host: String, port: Int, audioPort: Int, name: String)? {
        // AudioRelay discovery response is a protobuf message
        // For MVP, try to extract JSON or simple text
        if let text = String(data: data, encoding: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let host = json["host"] as? String ?? "unknown"
                let port = json["port"] as? Int ?? 59200
                let audioPort = json["audioPort"] as? Int ?? 59100
                let name = json["name"] as? String ?? "Unknown Server"
                return (host, port, audioPort, name)
            }

            // Text-based response
            if text.contains("AudioRelay") {
                return ("unknown", 59200, 59100, "AudioRelay Server")
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func addDiscoveredServer(
        host: String,
        port: Int = 59200,
        audioPort: Int = 59100,
        name: String = "AudioRelay Server"
    ) {
        let serverId = "\(host):\(port)"
        guard !discoveredIds.contains(serverId) else { return }
        discoveredIds.insert(serverId)

        let cleanHost = host.replacingOccurrences(of: "%", with: "")
        let server = ServerInfo(
            id: serverId,
            name: name,
            host: cleanHost,
            port: port,
            audioPort: audioPort
        )

        Task { @MainActor in
            self.onDiscover(server)
        }
    }

    /// Get the local broadcast address
    private func getBroadcastAddress() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addrFamily = ptr.pointee.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) && (flags & IFF_BROADCAST) != 0 {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    ptr.pointee.ifa_dstaddr,
                    socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil, 0,
                    NI_NUMERICHOST
                ) == 0 {
                    addr = String(cString: hostname)
                    break
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return addr
    }
}
