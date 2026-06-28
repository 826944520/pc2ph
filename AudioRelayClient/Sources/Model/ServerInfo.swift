import Foundation

/// Information about a discovered AudioRelay server
struct ServerInfo: Identifiable, Codable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let audioPort: Int
    let version: String
    let features: [String]
    let osVersion: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        port: Int = 59200,
        audioPort: Int = 59100,
        version: String = "0.27.5",
        features: [String] = [],
        osVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.audioPort = audioPort
        self.version = version
        self.features = features
        self.osVersion = osVersion
    }
}

/// Audio format configuration
struct AudioFormat: Equatable {
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let bitrate: Int

    static let defaultFormat = AudioFormat(
        sampleRate: 48000,
        channels: 2,
        bitsPerSample: 16,
        bitrate: 96000
    )
}

/// Network statistics
struct NetworkStats {
    var bytesReceived: UInt64 = 0
    var packetsReceived: UInt64 = 0
    var packetsLost: UInt64 = 0
    var averageLatency: Double = 0
    var maxLatency: Double = 0
    var underflowCount: UInt64 = 0
    var outOfOrderPackets: UInt64 = 0
}
