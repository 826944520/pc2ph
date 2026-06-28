import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ============================================================
// Opus C library FFI bindings
// ============================================================
//
// libopus must be available on the target platform:
//   - iOS:     Add 'opus-ios' pod in Podfile (included)
//   - Android: Add prebuilt libopus.so in app/src/main/jniLibs/
//   - macOS:   brew install opus
//   - Windows: Copy opus.dll next to executable
//   - Linux:   apt install libopus0
//
// C API:
//   OpusDecoder* opus_decoder_create(int32_t Fs, int channels, int* error)
//   int opus_decode(OpusDecoder*, const uint8_t*, int32_t len,
//                   opus_int16* pcm, int frame_size, int decode_fec)
//   void opus_decoder_destroy(OpusDecoder*)
//   int opus_decoder_ctl(OpusDecoder*, int request, ...)

// --- FFI Type Definitions ---

typedef OpusDecoderCreateNative = Pointer<Void> Function(
    Int32 Fs, Int32 channels, Pointer<Int32> error);
typedef OpusDecoderCreateDart = Pointer<Void> Function(
    int Fs, int channels, Pointer<Int32> error);

typedef OpusDecodeNative = Int32 Function(
    Pointer<Void> st, Pointer<Uint8> data, Int32 len,
    Pointer<Int16> pcm, Int32 frameSize, Int32 decodeFec);
typedef OpusDecodeDart = int Function(
    Pointer<Void> st, Pointer<Uint8> data, int len,
    Pointer<Int16> pcm, int frameSize, int decodeFec);

typedef OpusDecoderDestroyNative = Void Function(Pointer<Void> st);
typedef OpusDecoderDestroyDart = void Function(Pointer<Void> st);

typedef OpusDecoderCtlNative = Int32 Function(
    Pointer<Void> st, Int32 request);
typedef OpusDecoderCtlDart = int Function(
    Pointer<Void> st, int request);

/// Opus audio decoder wrapping libopus via dart:ffi.
class OpusDecoder {
  static const int opusResetState = 4028;
  static const int maxFrameSize = 5760; // 120ms at 48kHz

  final int sampleRate;
  final int channels;
  late final DynamicLibrary _lib;
  late final Pointer<Void> _decoder;

  late final OpusDecoderCreateDart _createFn;
  late final OpusDecodeDart _decodeFn;
  late final OpusDecoderDestroyDart _destroyFn;
  late final OpusDecoderCtlDart _ctlFn;

  OpusDecoder({
    this.sampleRate = 48000,
    this.channels = 2,
  }) {
    _lib = _loadOpusLibrary();
    _bindFunctions();
    _decoder = _createDecoder();
  }

  // --- Library Loading ---

  static DynamicLibrary _loadOpusLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libopus.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process(); // Statically linked
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libopus.0.dylib');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('opus.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libopus.so.0');
    }
    throw UnsupportedError('Unsupported platform for libopus');
  }

  void _bindFunctions() {
    _createFn = _lib.lookupFunction<OpusDecoderCreateNative, OpusDecoderCreateDart>(
      'opus_decoder_create',
    );
    _decodeFn = _lib.lookupFunction<OpusDecodeNative, OpusDecodeDart>(
      'opus_decode',
    );
    _destroyFn = _lib.lookupFunction<OpusDecoderDestroyNative, OpusDecoderDestroyDart>(
      'opus_decoder_destroy',
    );
    _ctlFn = _lib.lookupFunction<OpusDecoderCtlNative, OpusDecoderCtlDart>(
      'opus_decoder_ctl',
    );
  }

  Pointer<Void> _createDecoder() {
    final errorPtr = calloc<Int32>();
    final dec = _createFn(sampleRate, channels, errorPtr);
    final errorCode = errorPtr.value;
    calloc.free(errorPtr);

    if (dec == nullptr || errorCode != 0) {
      throw Exception('Failed to create Opus decoder (error: $errorCode)');
    }
    return dec;
  }

  // --- Decode ---

  /// Decode an Opus-encoded frame to PCM 16-bit signed integers (interleaved).
  Uint8List decode(Uint8List opusData) {
    final samplesCapacity = maxFrameSize * channels;
    final pcmPtr = calloc<Int16>(samplesCapacity);
    final opusPtr = calloc<Uint8>(opusData.length);

    // Copy opus input to native memory
    for (int i = 0; i < opusData.length; i++) {
      opusPtr[i] = opusData[i];
    }

    final samplesPerChannel = _decodeFn(
      _decoder,
      opusPtr,
      opusData.length,
      pcmPtr,
      maxFrameSize,
      0, // decode_fec = 0
    );

    calloc.free(opusPtr);

    if (samplesPerChannel < 0) {
      calloc.free(pcmPtr);
      throw Exception('Opus decode error: $samplesPerChannel');
    }

    // Copy PCM data back to Dart Uint8List
    final outputSize = samplesPerChannel * channels * 2; // 16-bit = 2 bytes
    final result = Uint8List(outputSize);
    final pcmBytes = pcmPtr.cast<Uint8>();
    for (int i = 0; i < outputSize; i++) {
      result[i] = pcmBytes[i];
    }

    calloc.free(pcmPtr);
    return result;
  }

  /// Reset decoder state (call after packet loss).
  void reset() {
    _ctlFn(_decoder, opusResetState);
  }

  /// Release native resources.
  void dispose() {
    _destroyFn(_decoder);
  }
}
