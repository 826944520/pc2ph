import Foundation
import Network

/// WebSocket control channel client for AudioRelay protocol.
/// Handles connection setup, feature negotiation, ping/pong, and command exchange.
final class WebSocketClient: Sendable {
    // MARK: - Types

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case negotiating
        case ready
        case disconnected
        case error(String)
    }

    enum ClientError: Error {
        case alreadyConnected
        case connectionFailed(String)
        case handshakeFailed(String)
        case timeout
        case invalidMessage
    }

    typealias StateHandler = @Sendable (State) -> Void
    typealias MessageHandler = @Sendable (Data) -> Void

    // MARK: - Properties

    private let host: String
    private let port: UInt16
    private let clientId: String
    private let clientVersion: String

    private var connection: NWConnection?
    private var state: State = .idle
    private var receiveBuffer = Data()
    private var pingTimer: Timer?

    var onStateChange: StateHandler?
    var onMessage: MessageHandler?
    var onServerHello: ((ServerHello) -> Void)?

    // MARK: - Init

    init(
        host: String,
        port: UInt16 = 59200,
        clientId: String = UUID().uuidString,
        clientVersion: String = "0.27.5"
    ) {
        self.host = host
        self.port = port
        self.clientId = clientId
        self.clientVersion = clientVersion
    }

    // MARK: - Connection

    func connect() {
        guard state == .idle || state == .disconnected else {
            updateState(.error("Already connected or connecting"))
            return
        }

        updateState(.connecting)

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols = [] // WebSocket upgrade will follow

        connection = NWConnection(to: endpoint, using: params)
        connection?.stateUpdateHandler = { [weak self] nwState in
            self?.handleNWState(nwState)
        }
        connection?.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        connection?.cancel()
        connection = nil
        updateState(.disconnected)
    }

    /// Send a protobuf-encoded message with length-prefix framing
    func send(_ messageData: Data) {
        let framed = frameMessage(messageData)
        connection?.send(content: framed, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.updateState(.error("Send failed: \(error.localizedDescription)"))
            }
        })
    }

    // MARK: - Handshake

    private func startHandshake() {
        updateState(.negotiating)

        // Build ClientHello message
        let hello = ClientHello(
            clientId: clientId,
            clientVersion: clientVersion,
            os: "iOS",
            osVersion: UIDevice.current.systemVersion,
            features: PlayerFeatures()
        )

        send(hello.encode())
    }

    // MARK: - Keepalive

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func sendPing() {
        var ping = Data()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        ping.append(protoFieldInt64(1, timestamp))
        send(ping)
    }

    // MARK: - Network State Handling

    private func handleNWState(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            updateState(.connected)
            performWebSocketUpgrade()
            startHandshake()
            startPingTimer()

        case .waiting(let error):
            updateState(.error("Waiting: \(error.localizedDescription)"))

        case .failed(let error):
            updateState(.error("Failed: \(error.localizedDescription)"))

        case .cancelled:
            updateState(.disconnected)

        default:
            break
        }
    }

    /// Perform HTTP to WebSocket upgrade
    private func performWebSocketUpgrade() {
        let wsKey = generateWebSocketKey()
        let upgradeRequest = """
        GET / HTTP/1.1\r
        Host: \(host):\(port)\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(wsKey)\r
        Sec-WebSocket-Version: 13\r
        \r\n
        """
        guard let data = upgradeRequest.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.updateState(.error("WebSocket upgrade failed: \(error.localizedDescription)"))
            }
        })

        // Start receiving after upgrade
        receiveWebSocketFrame()
    }

    private func generateWebSocketKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return Data(bytes).base64EncodedString()
    }

    // MARK: - WebSocket Frame Receive

    private func receiveWebSocketFrame() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.updateState(.error("Receive error: \(error.localizedDescription)"))
                return
            }

            if let data = data {
                self.handleReceivedData(data)
            }

            if !isComplete {
                self.receiveWebSocketFrame()
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        // Parse WebSocket frame
        guard data.count >= 2 else { return }

        let firstByte = data[0]
        let secondByte = data[1]
        let opcode = firstByte & 0x0F
        let isMasked = (secondByte & 0x80) != 0
        var payloadLength = UInt64(secondByte & 0x7F)
        var offset = 2

        // Extended payload length
        if payloadLength == 126 {
            guard data.count >= 4 else { return }
            payloadLength = UInt64(data[2...3].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
            offset = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else { return }
            payloadLength = data[2...9].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            offset = 10
        }

        // Masking key
        var mask: [UInt8] = []
        if isMasked {
            guard data.count >= offset + 4 else { return }
            mask = Array(data[offset..<offset + 4])
            offset += 4
        }

        // Payload
        let endOffset = offset + Int(payloadLength)
        guard data.count >= endOffset else { return }

        var payload = data.subdata(in: offset..<endOffset)
        if isMasked {
            for i in 0..<payload.count {
                payload[i] ^= mask[i % 4]
            }
        }

        switch opcode {
        case 0x01: // Text frame
            // Could contain JSON handshake response
            break
        case 0x02: // Binary frame
            // Protobuf message with length prefix
            receiveBuffer.append(payload)
            processReceiveBuffer()
        case 0x08: // Close frame
            disconnect()
        case 0x09: // Ping
            sendPong(payload)
        case 0x0A: // Pong
            break
        default:
            break
        }
    }

    private func processReceiveBuffer() {
        while let (message, remaining) = unframeMessage(from: receiveBuffer) {
            receiveBuffer = remaining
            onMessage?(message)
            try? parseServerHello(from: message)
        }
    }

    private func parseServerHello(from data: Data) throws {
        // Attempt to parse as server config response
        // The server hello contains: server_id(1), server_version(2), name(3), features(4), audio_config(5)
        // For MVP, we just forward raw messages and let the handler deal with them
    }

    private func sendPong(_ data: Data) {
        var frame = Data()
        frame.append(0x8A) // FIN + Pong opcode
        frame.append(UInt8(data.count))
        frame.append(data)
        connection?.send(content: frame, completion: .contentProcessed { _ in })
    }

    // MARK: - Helpers

    private func updateState(_ newState: State) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
            self?.onStateChange?(newState)
        }
    }
}
