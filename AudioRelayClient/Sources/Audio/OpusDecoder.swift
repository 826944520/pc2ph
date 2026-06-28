import Foundation
import AVFAudio

// ============================================================
// Opus Audio Decoder Wrapper
// ============================================================
//
// libopus integration for iOS:
//
// Option 1: Use XCFramework from Cocoapods/Carthage/SPM
//   Add: https://github.com/chrisballinger/Opus-iOS
//
// Option 2: Manual integration:
//   1. Download opus source: https://opus-codec.org/downloads/
//   2. Build for iOS arm64 with: ./configure --host=arm-apple-darwin
//   3. Create XCFramework with lipo
//   4. Add to Xcode project
//
// For MVP testing on simulator, we use a PCM pass-through fallback
// that works without libopus (no compression, high bandwidth).
//

/// Interface for audio decoding
protocol AudioDecoding: Sendable {
    var sampleRate: Int { get }
    var channels: Int { get }

    func decode(_ data: Data) throws -> Data
    func reset()
}

/// Opus audio decoder using libopus C library
final class OpusDecoder: AudioDecoding, @unchecked Sendable {
    let sampleRate: Int
    let channels: Int

    private let decoder: OpaquePointer
    private let frameSize: Int
    private let maxFrameSize: Int = 5760 // Max Opus frame size at 120ms, 48kHz

    /// Initialize Opus decoder
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (e.g. 48000)
    ///   - channels: Number of audio channels (e.g. 2)
    /// - Throws: Error if decoder creation fails
    init(sampleRate: Int = 48000, channels: Int = 2) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.frameSize = sampleRate / 50 // 20ms frame

        var opusErr: Int32 = 0
        guard let decoder = opus_decoder_create(
            Int32(sampleRate),
            Int32(channels),
            &opusErr
        ) else {
            throw DecoderError.createFailed(opusErr)
        }
        self.decoder = decoder
    }

    func decode(_ data: Data) throws -> Data {
        let pcmCapacity = maxFrameSize * channels * MemoryLayout<opus_int16>.size
        var pcmData = Data(count: pcmCapacity)

        let samplesDecoded = pcmData.withUnsafeMutableBytes { pcmPtr -> Int32 in
            return data.withUnsafeBytes { opusPtr in
                let pcm = pcmPtr.bindMemory(to: opus_int16.self).baseAddress!
                let opus = opusPtr.bindMemory(to: UInt8.self).baseAddress!
                return opus_decode(
                    decoder,
                    opus,
                    Int32(data.count),
                    pcm,
                    Int32(maxFrameSize),
                    0
                )
            }
        }

        guard samplesDecoded >= 0 else {
            throw DecoderError.decodeFailed(samplesDecoded)
        }

        // Trim to actual decoded size
        let actualSize = Int(samplesDecoded) * channels * MemoryLayout<opus_int16>.size
        return pcmData.prefix(actualSize)
    }

    func reset() {
        opus_decoder_ctl(decoder, OPUS_RESET_STATE)
    }

    deinit {
        opus_decoder_destroy(decoder)
    }

    enum DecoderError: Error {
        case createFailed(Int32)
        case decodeFailed(Int32)
    }
}

/// Opus decoder state
struct OpusDecoderState {
    let sampleRate: Int
    let channels: Int
    fileprivate var isInitialized: Bool

    init(sampleRate: Int = 48000, channels: Int = 2) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.isInitialized = false
    }
}

// ============================================================
// Opus C API declarations (bridging header or module import)
// ============================================================
// In a real project, these come from the opus C header (#include <opus.h>).
// For this SPM project, add the libopus XCFramework as a dependency.
// For now, we declare the necessary functions:

// #if canImport(libopus)
// import libopus
// #endif

// MARK: - Opus C Types & Functions

typealias opus_int16 = Int16
typealias opus_int32 = Int32

let OPUS_RESET_STATE: Int32 = 4028 // OPUS_RESET_STATE CTL request

// These would be provided by the libopus XCFramework:
// - opus_decoder_create(Float32, Int32, UnsafeMutablePointer<Int32>) -> OpaquePointer?
// - opus_decode(OpaquePointer, UnsafePointer<UInt8>?, Int32, UnsafeMutablePointer<opus_int16>?, Int32, Int32) -> Int32
// - opus_decoder_destroy(OpaquePointer)
// - opus_decoder_ctl(OpaquePointer, Int32)

// MARK: - External function declarations (will link against libopus)
@_silgen_name("opus_decoder_create")
func opus_decoder_create(_ Fs: opus_int32, _ channels: Int32, _ error: UnsafeMutablePointer<Int32>?) -> OpaquePointer?

@_silgen_name("opus_decode")
func opus_decode(_ st: OpaquePointer, _ data: UnsafePointer<UInt8>?, _ len: opus_int32, _ pcm: UnsafeMutablePointer<opus_int16>?, _ frame_size: Int32, _ decode_fec: Int32) -> Int32

@_silgen_name("opus_decoder_destroy")
func opus_decoder_destroy(_ st: OpaquePointer)

@_silgen_name("opus_decoder_ctl")
func opus_decoder_ctl(_ st: OpaquePointer, _ request: Int32, _ args: CVarArg...) -> Int32
