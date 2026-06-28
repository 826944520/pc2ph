import Foundation
import Network

/// Main controller that orchestrates WebSocket connection, UDP audio streaming,
/// Opus decoding, and audio playback for the AudioRelay iOS client.
@MainActor
final class AudioRelayManager: ObservableObject {
    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published var isPlaying: Bool = false
    @Published var volume: Float = 1.0 {
        didSet { audioPlayer?.setVolume(volume) }
    }
    @Published var stats: NetworkStats = NetworkStats()
    @Published var bufferFillLevel: Int = 0
    @Published var discoveredServers: [ServerInfo] = []
    @Published var errorMessage: String?

    // MARK: - Internal Properties

    private var wsClient: WebSocketClient?
    private var udpReceiver: UDPAudioReceiver?
    private var opusDecoder: OpusDecoder?
    private var audioPlayer: AudioPlayer?
    private var serverDiscoverer: ServerDiscoverer?
    private var currentServer: ServerInfo?

    private let audioFormat = AudioFormat.defaultFormat

    // MARK: - Server Discovery

    func startDiscovery() {
        connectionState = .discovering

        serverDiscoverer = ServerDiscoverer { [weak self] server in
            guard let self = self else { return }
            if !self.discoveredServers.contains(where: { $0.id == server.id }) {
                self.discoveredServers.append(server)
            }
        }
        serverDiscoverer?.start()
    }

    func stopDiscovery() {
        serverDiscoverer?.stop()
        serverDiscoverer = nil
        if case .discovering = connectionState {
            connectionState = .disconnected
        }
    }

    // MARK: - Connection

    func connect(to server: ServerInfo) {
        currentServer = server
        connectionState = .connecting(host: server.host)

        // Initialize audio pipeline
        do {
            opusDecoder = try OpusDecoder(
                sampleRate: audioFormat.sampleRate,
                channels: audioFormat.channels
            )

            audioPlayer = AudioPlayer(
                configuration: .init(
                    sampleRate: Double(audioFormat.sampleRate),
                    channels: AVAudioChannelCount(audioFormat.channels),
                    bitsPerSample: audioFormat.bitsPerSample,
                    bufferSize: 2048
                )
            )
            audioPlayer?.onStateChange = { [weak self] state in
                self?.handleAudioState(state)
            }
            audioPlayer?.setVolume(volume)
        } catch {
            connectionState = .error(error)
            errorMessage = "Failed to initialize audio: \(error.localizedDescription)"
            return
        }

        // Setup UDP receiver
        udpReceiver = UDPAudioReceiver(port: UInt16(server.audioPort))
        udpReceiver?.onPacket = { [weak self] packet in
            self?.handleAudioPacket(packet)
        }
        udpReceiver?.onStateChange = { [weak self] state in
            self?.handleUDPState(state)
        }

        // Setup WebSocket
        wsClient = WebSocketClient(
            host: server.host,
            port: UInt16(server.port),
            clientId: getDeviceId(),
            clientVersion: "0.27.5"
        )

        wsClient?.onStateChange = { [weak self] state in
            self?.handleWSState(state)
        }

        wsClient?.onMessage = { [weak self] data in
            self?.handleWSMessage(data)
        }

        wsClient?.onServerHello = { [weak self] hello in
            self?.handleServerHello(hello)
        }

        wsClient?.connect()
    }

    func disconnect() {
        wsClient?.disconnect()
        udpReceiver?.stop()
        audioPlayer?.stop()
        wsClient = nil
        udpReceiver = nil
        audioPlayer = nil
        opusDecoder = nil
        connectionState = .disconnected
        isPlaying = false
    }

    // MARK: - Message Handling

    private func handleWSState(_ state: WebSocketClient.State) {
        switch state {
        case .connected:
            // WebSocket established, waiting for handshake
            break
        case .ready:
            // Handshake complete, start UDP listener
            connectionState = .connected(currentServer!)
            startAudioStreaming()
        case .disconnected, .error:
            if isPlaying {
                // Attempt reconnect
                attemptReconnect()
            }
        default:
            break
        }
    }

    private func handleWSMessage(_ data: Data) {
        // Handle control messages from server
        // For MVP: mostly server config, ping responses, stop commands
        // Future: parse protobuf messages for volume, stats, etc.
    }

    private func handleServerHello(_ hello: ServerHello) {
        // Server sent its configuration, we can now start streaming
    }

    private func handleUDPState(_ state: UDPAudioReceiver.State) {
        switch state {
        case .listening:
            break
        case .error(let message):
            errorMessage = "UDP Error: \(message)"
        default:
            break
        }
    }

    private func handleAudioState(_ state: AudioPlayer.State) {
        switch state {
        case .playing:
            isPlaying = true
            connectionState = .streaming(currentServer!)
        case .paused:
            isPlaying = false
        case .stopped, .error:
            isPlaying = false
        default:
            break
        }
    }

    // MARK: - Audio Pipeline

    private func startAudioStreaming() {
        do {
            try udpReceiver?.start()
        } catch {
            errorMessage = "Failed to start audio receiver: \(error.localizedDescription)"
        }
    }

    private func handleAudioPacket(_ packet: UDPAudioReceiver.AudioPacket) {
        guard let decoder = opusDecoder else { return }

        do {
            let pcmData = try decoder.decode(packet.data)
            audioPlayer?.feed(pcmData)

            // Update stats periodically
            if let udpStats = udpReceiver?.stats {
                stats = udpStats
            }
            bufferFillLevel = audioPlayer?.bufferFillLevel ?? 0
        } catch {
            // Silently skip decode errors for robustness
        }
    }

    // MARK: - Reconnection

    private func attemptReconnect() {
        guard let server = currentServer else { return }

        var attempt = 0
        let maxAttempts = 10
        let baseDelay: TimeInterval = 1.0

        func reconnect() {
            guard attempt < maxAttempts else {
                connectionState = .error(
                    NSError(domain: "AudioRelay", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Max reconnect attempts reached"])
                )
                return
            }

            attempt += 1
            connectionState = .reconnecting(server, attempt: attempt)

            let delay = baseDelay * pow(2.0, Double(attempt - 1))
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.connect(to: server)
            }
        }

        reconnect()
    }

    // MARK: - Device Identity

    private func getDeviceId() -> String {
        let key = "AudioRelayClient.deviceId"
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}

// MARK: - Preview Helper

extension AudioRelayManager {
    static func preview() -> AudioRelayManager {
        let manager = AudioRelayManager()
        manager.discoveredServers = [
            ServerInfo(name: "My PC", host: "192.168.1.100"),
            ServerInfo(name: "Living Room PC", host: "192.168.1.101"),
        ]
        return manager
    }
}
