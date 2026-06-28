import SwiftUI

/// Application entry point
@main
struct AudioRelayClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

/// For SPM library usage without @main, use this instead:
// public struct AudioRelayClient {
//     public static func makeContentView() -> some View {
//         ContentView()
//     }
// }
