import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/server_info.dart';
import '../models/connection_state.dart' as model;
import '../network/websocket_client.dart';
import '../network/udp_audio_receiver.dart';
import '../audio/opus_decoder.dart';
import '../audio/audio_player.dart';
import '../discovery/server_discoverer.dart';

/// Main state manager for the AudioRelay client.
/// Coordinates network, audio decoding, and playback.
class AudioRelayManager extends ChangeNotifier {
  // --- Connection State ---
  model.ConnectionState _connectionState = model.ConnectionState.disconnected;
  model.ConnectionState get connectionState => _connectionState;

  ServerInfo? _currentServer;
  ServerInfo? get currentServer => _currentServer;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // --- Audio ---
  double _volume = 1.0;
  double get volume => _volume;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  int _bufferFill = 0;
  int get bufferFill => _bufferFill;

  // --- Servers ---
  final List<ServerInfo> discoveredServers = [];

  // --- Internal ---
  AudioRelayWebSocket? _ws;
  UDPAudioReceiver? _udp;
  OpusDecoder? _opus;
  PCMAudioPlayer? _player;
  ServerDiscoverer? _discoverer;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  final List<StreamSubscription> _subs = [];

  // ================================================================
  // Server Discovery
  // ================================================================

  Future<void> startDiscovery() async {
    _setState(model.ConnectionState.discovering);

    _discoverer = ServerDiscoverer();
    _subs.add(_discoverer!.onDiscover.listen((server) {
      if (!discoveredServers.any((s) => s.id == server.id)) {
        discoveredServers.add(server);
        notifyListeners();
      }
    }));

    await _discoverer!.start();
  }

  void stopDiscovery() {
    _discoverer?.stop();
    _discoverer = null;
    if (_connectionState == model.ConnectionState.discovering) {
      _setState(model.ConnectionState.disconnected);
    }
  }

  // ================================================================
  // Connection
  // ================================================================

  Future<void> connect(ServerInfo server) async {
    _currentServer = server;
    _reconnectAttempt = 0;
    _setState(model.ConnectionState.connecting);

    // Init audio stack
    try {
      _opus = OpusDecoder(
        sampleRate: 48000,
        channels: 2,
      );
      _player = PCMAudioPlayer(sampleRate: 48000, channels: 2);
    } catch (e) {
      _setError('Failed to init audio: $e');
      return;
    }

    // UDP receiver
    _udp = UDPAudioReceiver(port: server.audioPort);
    _subs.add(_udp!.packetStream.listen(_handleAudioPacket));
    _subs.add(_udp!.stateStream.listen((s) {
      if (s == UDPState.error) _setError('UDP receive error');
    }));

    // WebSocket
    _ws = AudioRelayWebSocket(
      host: server.host,
      port: server.port,
    );

    _subs.add(_ws!.stateStream.listen(_handleWSState));
    _subs.add(_ws!.messageStream.listen(_handleWSMessage));

    await _ws!.connect();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _ws?.disconnect();
    _udp?.stop();
    _player?.stop();
    _opus?.dispose();

    _ws = null;
    _udp = null;
    _player = null;
    _opus = null;

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();

    _isPlaying = false;
    _setState(model.ConnectionState.disconnected);
  }

  // ================================================================
  // WebSocket Handlers
  // ================================================================

  void _handleWSState(WebSocketState state) {
    switch (state) {
      case WebSocketState.connected:
        _setState(model.ConnectionState.connected);
        _startUDP();
      case WebSocketState.disconnected:
        if (_isPlaying) _attemptReconnect();
      case WebSocketState.error:
        if (_isPlaying) _attemptReconnect();
      default:
        break;
    }
  }

  void _handleWSMessage(Uint8List data) {
    // Handle server control messages
    // For MVP: server config, stats, stop commands
  }

  void _startUDP() {
    _udp?.start();
  }

  // ================================================================
  // Audio Pipeline
  // ================================================================

  void _handleAudioPacket(AudioPacket packet) {
    try {
      final pcm = _opus!.decode(packet.data);
      _player!.feed(pcm);
      _bufferFill = _player!.bufferSize;

      if (!_isPlaying) {
        _isPlaying = true;
        _setState(model.ConnectionState.streaming);
      }

      notifyListeners();
    } catch (_) {
      // Skip decode errors
    }
  }

  // ================================================================
  // Reconnection
  // ================================================================

  void _attemptReconnect() {
    if (_currentServer == null) return;

    _reconnectAttempt++;
    if (_reconnectAttempt > 10) {
      _setError('Max reconnect attempts reached');
      return;
    }

    _setState(model.ConnectionState.reconnecting);

    final delay = Duration(
        milliseconds: 1000 * (1 << min(_reconnectAttempt - 1, 6)));
    _reconnectTimer = Timer(delay, () {
      if (_currentServer != null) {
        connect(_currentServer!);
      }
    });
  }

  // ================================================================
  // Volume
  // ================================================================

  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    _player?.setVolume(_volume);
    notifyListeners();
  }

  // ================================================================
  // Internal
  // ================================================================

  void _setState(model.ConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _setState(model.ConnectionState.error);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
