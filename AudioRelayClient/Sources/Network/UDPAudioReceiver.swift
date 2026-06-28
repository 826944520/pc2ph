import Foundation
import Darwin

/// UDP audio data receiver for AudioRelay protocol.
/// Receives Opus-encoded audio packets on port 59100.
/// Uses POSIX BSD sockets for reliable cross-platform UDP reception.
final class UDPAudioReceiver: Sendable {
    // MARK: - Types

    enum State {
        case idle
        case listening
        case error(String)
        case stopped
    }

    typealias AudioPacketHandler = @Sendable (AudioPacket) -> Void
    typealias StateHandler = @Sendable (State) -> Void

    struct AudioPacket {
        let sequenceNumber: UInt32
        let timestamp: Int64
        let tick: Int64
        let isRetransmission: Bool
        let data: Data
    }

    // MARK: - Properties

    private let port: UInt16
    private var socketFD: Int32 = -1
    private var receiveQueue: DispatchQueue?
    private var isRunning = false
    private var state: State = .idle

    private var lastSequenceNumber: UInt32 = 0
    private var packetLossCount: UInt64 = 0
    private var totalPackets: UInt64 = 0
    private let maxPacketSize = 65536

    var onPacket: AudioPacketHandler?
    var onStateChange: StateHandler?

    init(port: UInt16 = 59100) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start() throws {
        guard state == .idle || state == .stopped else { return }

        // Create UDP socket
        socketFD = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else {
            throw ReceiverError.socketCreationFailed(String(cString: strerror(errno)))
        }

        // Set socket options
        var reuseAddr: Int32 = 1
        guard Darwin.setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size)) >= 0 else {
            Darwin.close(socketFD)
            throw ReceiverError.socketOptionFailed(String(cString: strerror(errno)))
        }

        // Set receive timeout (1 second)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        Darwin.setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Set large receive buffer
        var rcvBuf: Int32 = 256 * 1024
        Darwin.setsockopt(socketFD, SOL_SOCKET, SO_RCVBUF, &rcvBuf, socklen_t(MemoryLayout<Int32>.size))

        // Bind to port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult >= 0 else {
            Darwin.close(socketFD)
            throw ReceiverError.bindFailed(String(cString: strerror(errno)))
        }

        updateState(.listening)
        isRunning = true

        // Start receive loop on background queue
        receiveQueue = DispatchQueue(label: "com.audiorelay.udp.receive", qos: .userInitiated)
        receiveQueue?.async { [weak self] in
            self?.receiveLoop()
        }
    }

    func stop() {
        isRunning = false
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
        receiveQueue = nil
        updateState(.stopped)
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: maxPacketSize)

        while isRunning {
            let bytesRead = Darwin.recv(socketFD, &buffer, maxPacketSize, 0)

            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                processAudioPacket(data)
            } else if bytesRead == 0 {
                // Socket closed
                break
            } else {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    // Timeout, continue listening
                    continue
                }
                if isRunning {
                    updateState(.error("recv error: \(String(cString: strerror(err)))"))
                }
                break
            }
        }
    }

    // MARK: - Packet Processing

    private func processAudioPacket(_ data: Data) {
        // AudioRelay UDP packet format (reverse-engineered):
        //
        // The packet structure is approximately:
        // - Protobuf-encoded StreamData message:
        //   - field 1: tick (int64) - monotonic counter
        //   - field 2: timestamp_ms (int64)
        //   - field 3: audio_data (bytes) - Opus-encoded frame
        //   - field 4: is_retransmission (bool)
        //   - field 5: sequence_number (int32)

        do {
            let packet = try parseStreamData(data)
            totalPackets += 1

            // Detect packet loss
            if lastSequenceNumber > 0 && packet.sequenceNumber > lastSequenceNumber + 1 {
                packetLossCount += UInt64(packet.sequenceNumber - lastSequenceNumber - 1)
            }
            lastSequenceNumber = packet.sequenceNumber

            onPacket?(packet)
        } catch {
            // Skip malformed packets
        }
    }

    /// Parse StreamData protobuf message from raw bytes
    private func parseStreamData(_ data: Data) throws -> AudioPacket {
        var tick: Int64 = 0
        var timestampMs: Int64 = 0
        var audioData = Data()
        var isRetransmission = false
        var sequenceNumber: UInt32 = 0

        // Simple protobuf wire format parser
        var offset = 0
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try readTag(data, offset: offset)
            offset = newOffset

            switch (fieldNumber, wireType) {
            case (1, 0): // tick (varint)
                (tick, offset) = try readVarint(data, offset: offset)
            case (2, 0): // timestamp_ms (varint)
                (timestampMs, offset) = try readVarint(data, offset: offset)
            case (3, 2): // audio_data (length-delimited)
                (audioData, offset) = try readLengthDelimited(data, offset: offset)
            case (4, 0): // is_retransmission (varint/bool)
                let (val, newOff): (Int64, Int) = try readVarint(data, offset: offset)
                isRetransmission = val != 0
                offset = newOff
            case (5, 0): // sequence_number (varint)
                let (val, newOff): (Int64, Int) = try readVarint(data, offset: offset)
                sequenceNumber = UInt32(val)
                offset = newOff
            default:
                // Skip unknown field
                offset = try skipField(data, offset: offset, wireType: wireType)
            }
        }

        return AudioPacket(
            sequenceNumber: sequenceNumber,
            timestamp: timestampMs,
            tick: tick,
            isRetransmission: isRetransmission,
            data: audioData
        )
    }

    // MARK: - Statistics

    var stats: NetworkStats {
        return NetworkStats(
            packetsReceived: totalPackets,
            packetsLost: packetLossCount
        )
    }

    // MARK: - Helpers

    private func updateState(_ newState: State) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
            self?.onStateChange?(newState)
        }
    }

    // --- Low-level Protobuf Wire Format Parsing ---

    private func readTag(_ data: Data, offset: Int) throws -> (Int, Int, Int) {
        let (raw, newOffset) = try readVarint(data, offset: offset)
        let fieldNumber = Int(raw >> 3)
        let wireType = Int(raw & 0x07)
        return (fieldNumber, wireType, newOffset)
    }

    private func readVarint(_ data: Data, offset: Int) throws -> (Int64, Int) {
        var result: Int64 = 0
        var shift: Int64 = 0
        var idx = offset
        while idx < data.count {
            let byte = data[idx]
            idx += 1
            result |= Int64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return (result, idx)
            }
            shift += 7
            if shift >= 64 {
                throw ReceiverError.invalidMessage
            }
        }
        throw ReceiverError.invalidMessage
    }

    private func readLengthDelimited(_ data: Data, offset: Int) throws -> (Data, Int) {
        let (length, newOffset) = try readVarint(data, offset: offset)
        let endOffset = newOffset + Int(length)
        guard endOffset <= data.count else { throw ReceiverError.invalidMessage }
        return (data.subdata(in: newOffset..<endOffset), endOffset)
    }

    private func skipField(_ data: Data, offset: Int, wireType: Int) throws -> Int {
        switch wireType {
        case 0: // varint
            let (_, newOffset) = try readVarint(data, offset: offset)
            return newOffset
        case 1: // 64-bit
            return min(offset + 8, data.count)
        case 2: // length-delimited
            let (_, newOffset) = try readLengthDelimited(data, offset: offset)
            return newOffset
        case 5: // 32-bit
            return min(offset + 4, data.count)
        default:
            return data.count
        }
    }

    enum ReceiverError: Error {
        case socketCreationFailed(String)
        case socketOptionFailed(String)
        case bindFailed(String)
        case invalidMessage
        case parseError(String)
    }
}
