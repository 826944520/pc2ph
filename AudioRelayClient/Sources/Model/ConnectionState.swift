import Foundation

/// Connection state machine for the AudioRelay client
enum ConnectionState: Equatable {
    case disconnected
    case discovering
    case connecting(host: String)
    case connected(ServerInfo)
    case streaming(ServerInfo)
    case reconnecting(ServerInfo, attempt: Int)
    case error(Error)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.discovering, .discovering): return true
        case (.connecting(let lh), .connecting(let rh)): return lh == rh
        case (.connected(let li), .connected(let ri)): return li.id == ri.id
        case (.streaming(let li), .streaming(let ri)): return li.id == ri.id
        case (.reconnecting(let li, let la), .reconnecting(let ri, let ra)):
            return li.id == ri.id && la == ra
        case (.error, .error): return true
        default: return false
        }
    }
}
