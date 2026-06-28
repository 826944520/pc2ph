import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// PCM audio player that feeds decoded audio data to the platform
/// audio system via a ring buffer + periodic output.
///
/// This uses a simple platform-agnostic approach. In production,
/// integrate with flutter_sound or a platform channel to
/// AVAudioEngine (iOS) / AudioTrack (Android) for lowest latency.
class PCMAudioPlayer {
  final int sampleRate;
  final int channels;
  final Queue<Uint8List> _buffer = Queue<Uint8List>();
  final int _maxBufferSize; // max frames to buffer

  Timer? _playbackTimer;
  bool _isPlaying = false;
  final _stateController = StreamController<PlayerState>.broadcast();

  Stream<PlayerState> get stateStream => _stateController.stream;
  bool get isPlaying => _isPlaying;
  int get bufferSize => _buffer.length;

  PCMAudioPlayer({
    this.sampleRate = 48000,
    this.channels = 2,
    int maxBufferMs = 500,
  }) : _maxBufferSize = maxBufferMs * sampleRate ~/ 1000;

  /// Feed decoded PCM data (16-bit interleaved) into the playback buffer.
  void feed(Uint8List pcmData) {
    if (_buffer.length >= _maxBufferSize) {
      _buffer.removeFirst(); // Drop oldest to prevent latency buildup
    }
    _buffer.add(pcmData);

    if (!_isPlaying && _buffer.length >= 3) {
      start();
    }
  }

  void start() {
    if (_isPlaying) return;
    _isPlaying = true;
    _emitState(PlayerState.playing);

    // In a real implementation, this would use a platform channel
    // to feed PCM data to the native audio system.
    // For now, this serves as the buffer management layer.
    _playbackTimer = Timer.periodic(
      Duration(milliseconds: 1000 * _buffer.length * 20 ~/ sampleRate),
      _playbackTick,
    );
  }

  void _playbackTick(Timer timer) {
    if (_buffer.isEmpty && _isPlaying) {
      _emitState(PlayerState.underflow);
      return;
    }

    // Pop one frame and "play" it
    // In production: route to native audio sink
    _buffer.removeFirst();
  }

  void pause() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _emitState(PlayerState.paused);
  }

  void stop() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _buffer.clear();
    _emitState(PlayerState.stopped);
  }

  void setVolume(double volume) {
    // In production: set platform audio volume
  }

  void dispose() {
    stop();
    _stateController.close();
  }

  void _emitState(PlayerState state) {
    _stateController.add(state);
  }
}

// ============================================================
// Platform audio method channel (Android AudioTrack / iOS AVAudioEngine)
// ============================================================
// Uncomment and implement in the platform-specific folders:
//
// Method channel: 'com.audiorelay/audio'
//   - 'start': {sampleRate: int, channels: int, bufferSize: int}
//   - 'write': Uint8List (PCM 16-bit interleaved)
//   - 'stop': {}
//   - 'setVolume': {volume: double}
//
// Android implementation: AudioTrack with WRITE_BLOCKING mode
// iOS implementation: AVAudioEngine + AVAudioPlayerNode with tap

enum PlayerState {
  playing,
  paused,
  stopped,
  underflow,
}
