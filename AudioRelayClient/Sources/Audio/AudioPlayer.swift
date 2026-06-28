import Foundation
import AVFAudio

/// Real-time audio player using AVAudioEngine.
/// Receives decoded PCM audio data and plays through the device speakers/headphones.
final class AudioPlayer: NSObject, Sendable {
    // MARK: - Configuration

    struct Configuration {
        let sampleRate: Double
        let channels: AVAudioChannelCount
        let bitsPerSample: Int
        var bufferSize: AVAudioFrameCount

        static let `default` = Configuration(
            sampleRate: 48000,
            channels: 2,
            bitsPerSample: 16,
            bufferSize: 2048
        )
    }

    // MARK: - Types

    enum State: Equatable {
        case idle
        case ready
        case playing
        case paused
        case error(String)
        case stopped
    }

    typealias StateHandler = @Sendable (State) -> Void

    // MARK: - Properties

    private let config: Configuration
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let format: AVAudioFormat
    private var audioBuffer: RingBuffer<Data>

    private var state: State = .idle
    var onStateChange: StateHandler?

    // MARK: - Init

    init(configuration: Configuration = .default, bufferCapacity: Int = 32) {
        self.config = configuration
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()

        // Configure audio format
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: config.sampleRate,
            channels: config.channels,
            interleaved: false
        ) else {
            fatalError("Failed to create AVAudioFormat")
        }
        self.format = audioFormat

        // Ring buffer for audio data (32 frames ~640ms at 20ms/frame)
        self.audioBuffer = RingBuffer(capacity: bufferCapacity)

        super.init()

        setupAudioEngine()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        let bufferSize = config.bufferSize
        engine.mainMixerNode.outputFormat(forBus: 0)

        do {
            try engine.start()
            state = .ready
            onStateChange?(.ready)
        } catch {
            state = .error("Engine start failed: \(error.localizedDescription)")
            onStateChange?(state)
            return
        }

        // Start the playback loop
        startPlaybackLoop()
    }

    // MARK: - Playback

    /// Feed decoded PCM audio data into the playback buffer
    func feed(_ pcmData: Data) {
        audioBuffer.push(pcmData)

        // Auto-start playback on first data
        if state == .ready && audioBuffer.count >= 3 {
            startPlaying()
        }
    }

    private func startPlaying() {
        guard state == .ready else { return }
        playerNode.play()
        state = .playing
        onStateChange?(.playing)
    }

    private func stopPlaying() {
        playerNode.stop()
        state = .stopped
        onStateChange?(.stopped)
    }

    private func startPlaybackLoop() {
        let frameCapacity = config.bufferSize
        let bytesPerFrame = Int(config.channels) * (config.bitsPerSample / 8)

        let playbackQueue = DispatchQueue(label: "com.audiorelay.audio.playback", qos: .userInitiated)

        playerNode.installTap(
            onBus: 0,
            bufferSize: frameCapacity,
            format: format
        ) { [weak self] buffer, _ in
            guard let self = self else { return }

            guard let pcmBuffer = buffer as? AVAudioPCMBuffer,
                  let channelData = pcmBuffer.int16ChannelData else {
                return
            }

            let framesInBuffer = Int(pcmBuffer.frameCapacity)
            let totalBytes = framesInBuffer * bytesPerFrame

            // Get audio data from ring buffer
            let audioData = self.audioBuffer.pop(maxBytes: totalBytes)

            if audioData.isEmpty {
                // Underflow: fill with silence
                for channel in 0..<Int(self.config.channels) {
                    memset(channelData[channel], 0, framesInBuffer * MemoryLayout<Int16>.size)
                }
                return
            }

            // Copy data to PCM buffer (non-interleaved format)
            audioData.withUnsafeBytes { rawPtr in
                let samples = rawPtr.bindMemory(to: Int16.self)
                let sampleCount = min(samples.count, framesInBuffer * Int(self.config.channels))

                // De-interleave samples to channels
                let channelCount = Int(self.config.channels)
                for i in 0..<sampleCount {
                    let channel = i % channelCount
                    let frameIndex = i / channelCount
                    guard frameIndex < framesInBuffer else { continue }
                    channelData[channel][frameIndex] = samples[i]
                }
            }

            pcmBuffer.frameLength = AVAudioFrameCount(min(
                audioData.count / bytesPerFrame,
                framesInBuffer
            ))
        }
    }

    // MARK: - Control

    func pause() {
        playerNode.pause()
        state = .paused
        onStateChange?(.paused)
    }

    func resume() {
        playerNode.play()
        state = .playing
        onStateChange?(.playing)
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        state = .stopped
        onStateChange?(.stopped)
    }

    func setVolume(_ volume: Float) {
        playerNode.volume = max(0, min(1, volume))
    }

    // MARK: - Diagnostics

    var bufferFillLevel: Int { audioBuffer.count }
    var isUnderflowing: Bool { state == .playing && audioBuffer.isEmpty }
}

// MARK: - Thread-Safe Ring Buffer

/// Thread-safe ring buffer for audio data
final class RingBuffer<T>: @unchecked Sendable {
    private var buffer: [T?]
    private let capacity: Int
    private var readIndex = 0
    private var writeIndex = 0
    private let lock = NSLock()

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return writeIndex - readIndex
    }

    var isEmpty: Bool { count == 0 }
    var isFull: Bool { count >= capacity }

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    func push(_ item: T) {
        lock.lock()
        defer { lock.unlock() }

        if writeIndex - readIndex >= capacity {
            // Drop oldest frame (buffer is full)
            readIndex += 1
        }
        buffer[writeIndex % capacity] = item
        writeIndex += 1
    }

    func pop() -> T? {
        lock.lock()
        defer { lock.unlock() }

        guard readIndex < writeIndex else { return nil }
        let item = buffer[readIndex % capacity]
        buffer[readIndex % capacity] = nil
        readIndex += 1
        return item
    }

    /// Pop up to maxBytes of data, merging multiple items if needed
    func pop(maxBytes: Int) -> Data where T == Data {
        lock.lock()
        defer { lock.unlock() }

        var result = Data()
        while result.count < maxBytes && readIndex < writeIndex {
            guard let item = buffer[readIndex % capacity] else { break }
            buffer[readIndex % capacity] = nil
            readIndex += 1

            let remaining = maxBytes - result.count
            if item.count <= remaining {
                result.append(item)
            } else {
                // Partial read: put remaining back
                result.append(item.prefix(remaining))
                let remainder = item.suffix(item.count - remaining)
                // Push remainder back at front
                readIndex -= 1
                buffer[readIndex % capacity] = remainder
                break
            }
        }
        return result
    }
}
