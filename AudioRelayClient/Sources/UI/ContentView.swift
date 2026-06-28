import SwiftUI

/// Main view for the AudioRelay iOS client
struct ContentView: View {
    @StateObject private var manager = AudioRelayManager()
    @State private var showManualConnect = false
    @State private var manualIP = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status banner
                statusBanner

                // Main content
                Group {
                    switch manager.connectionState {
                    case .disconnected, .discovering:
                        serverListView
                    case .connecting:
                        connectingView
                    case .connected:
                        connectedView
                    case .streaming:
                        streamingView
                    case .reconnecting:
                        reconnectingView
                    case .error:
                        errorView
                    }
                }
            }
            .navigationTitle("AudioRelay")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showManualConnect) {
                manualConnectView
            }
            .sheet(isPresented: $showSettings) {
                settingsView
            }
        }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if manager.isPlaying {
                AudioLevelIndicator()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Server List

    private var serverListView: some View {
        List {
            Section("Discovered Servers") {
                if manager.discoveredServers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Searching for servers...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 32)
                        Spacer()
                    }
                } else {
                    ForEach(manager.discoveredServers) { server in
                        ServerRow(server: server) {
                            manager.connect(to: server)
                        }
                    }
                }
            }

            Section {
                Button(action: { showManualConnect = true }) {
                    Label("Manual Connect", systemImage: "network.badge.shield")
                }
            }
        }
        .refreshable {
            manager.startDiscovery()
        }
        .onAppear {
            manager.startDiscovery()
        }
        .onDisappear {
            manager.stopDiscovery()
        }
    }

    // MARK: - Connection States

    private var connectingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting...")
                .font(.headline)

            Text("Establishing connection to server")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                manager.disconnect()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Connected!")
                .font(.title2)

            Text("Starting audio stream...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView()
                .padding(.top, 8)

            Button("Disconnect") {
                manager.disconnect()
            }
            .buttonStyle(.bordered)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var streamingView: some View {
        VStack(spacing: 24) {
            // Now Playing animation
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(.blue.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, options: .repeat(.periodic(delay: 0.3)))
            }

            Text("Streaming Audio")
                .font(.title2.bold())

            if let server = currentServerFromState {
                Text("From: \(server.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Volume control
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $manager.volume, in: 0...1)
                        .tint(.blue)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
                Text("Volume: \(Int(manager.volume * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            // Stats
            HStack(spacing: 32) {
                StatBadge(
                    icon: "arrow.down.circle",
                    value: formatBytes(manager.stats.bytesReceived),
                    label: "Received"
                )

                StatBadge(
                    icon: "clock",
                    value: String(format: "%.1fms", manager.stats.averageLatency),
                    label: "Latency"
                )

                StatBadge(
                    icon: "antenna.radiowaves.left.and.right",
                    value: "\(manager.bufferFillLevel)",
                    label: "Buffer"
                )
            }

            Spacer()

            // Disconnect button
            Button(role: .destructive, action: {
                manager.disconnect()
            }) {
                Label("Disconnect", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reconnectingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.3)

            Text("Reconnecting...")
                .font(.headline)

            if case .reconnecting(_, let attempt) = manager.connectionState {
                Text("Attempt \(attempt)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                manager.disconnect()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Connection Error")
                .font(.title3)

            if let error = manager.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack {
                Button("Retry") {
                    if let server = currentServerFromState {
                        manager.connect(to: server)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Go Back") {
                    manager.disconnect()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Manual Connect

    private var manualConnectView: some View {
        NavigationStack {
            Form {
                Section("Server Address") {
                    TextField("IP Address (e.g. 192.168.1.100)", text: $manualIP)
                        .keyboardType(.decimalPad)
                        .autocapitalization(.none)

                    HStack {
                        Text("Port")
                        Spacer()
                        Text("59200")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Audio Port")
                        Spacer()
                        Text("59100")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Connect") {
                        let server = ServerInfo(
                            name: "Manual Server",
                            host: manualIP,
                            port: 59200,
                            audioPort: 59100
                        )
                        manager.connect(to: server)
                        showManualConnect = false
                    }
                    .disabled(manualIP.isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Manual Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showManualConnect = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Settings

    private var settingsView: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    HStack {
                        Text("Sample Rate")
                        Spacer()
                        Text("48 kHz")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Channels")
                        Spacer()
                        Text("Stereo")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Bitrate")
                        Spacer()
                        Text("96 kbps")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Compatibility", value: "AudioRelay v0.27.5")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch manager.connectionState {
        case .disconnected: return .gray
        case .discovering: return .orange
        case .connecting: return .yellow
        case .connected: return .blue
        case .streaming: return .green
        case .reconnecting: return .orange
        case .error: return .red
        }
    }

    private var statusText: String {
        switch manager.connectionState {
        case .disconnected: return "Disconnected"
        case .discovering: return "Searching..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .streaming: return "Streaming Audio"
        case .reconnecting(_, let attempt): return "Reconnecting (\(attempt))"
        case .error: return "Error"
        }
    }

    private var currentServerFromState: ServerInfo? {
        switch manager.connectionState {
        case .connected(let info), .streaming(let info), .reconnecting(let info, _):
            return info
        default:
            return nil
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: - Subviews

struct ServerRow: View {
    let server: ServerInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                    Text(server.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .tint(.primary)
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.caption.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}

/// Animated audio level indicator
struct AudioLevelIndicator: View {
    @State private var animationPhase: Double = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 2, height: 6 + 10 * sin(animationPhase + Double(index) * 0.5))
            }
        }
        .animation(.linear(duration: 0.3).repeatForever(autoreverses: false), value: animationPhase)
        .onAppear {
            animationPhase = .pi * 2
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
