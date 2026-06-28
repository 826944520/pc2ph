import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'protocol/messages.dart';

/// WebSocket control channel for AudioRelay protocol.
class AudioRelayWebSocket {
  final String host;
  final int port;
  final String clientId;
  final String clientVersion;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  final Queue<Uint8List> _receiveBuffer = Queue<Uint8List>();

  bool _connected = false;
  String? lastError;

  final _stateController = StreamController<WebSocketState>.broadcast();
  final _messageController = StreamController<Uint8List>.broadcast();

  Stream<WebSocketState> get stateStream => _stateController.stream;
  Stream<Uint8List> get messageStream => _messageController.stream;
  bool get isConnected => _connected;

  AudioRelayWebSocket({
    required this.host,
    this.port = 59200,
    String? clientId,
    this.clientVersion = '0.27.5',
  }) : clientId = clientId ?? _generateId();

  static String _generateId() {
    final r = Random();
    return List.generate(32, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  Future<void> connect() async {
    _emitState(WebSocketState.connecting);

    try {
      final uri = Uri.parse('ws://$host:$port/');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;
      _connected = true;
      _emitState(WebSocketState.connected);

      _subscription = _channel!.stream.listen(
        _handleData,
        onError: (error) {
          lastError = error.toString();
          _emitState(WebSocketState.error);
        },
        onDone: _handleDone,
      );

      _sendHandshake();
    } catch (e) {
      lastError = e.toString();
      _emitState(WebSocketState.error);
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _connected = false;
    _emitState(WebSocketState.disconnected);
  }

  void send(Uint8List data) {
    if (!_connected) return;
    final framed = AudioRelayProtocol.frameMessage(data);
    _channel?.sink.add(framed);
  }

  void _sendHandshake() {
    final hello = AudioRelayProtocol.buildClientHello(
      clientId: clientId,
      clientVersion: clientVersion,
      os: 'Flutter',
      osVersion: '1.0.0',
    );
    send(hello);
    _startPingTimer();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_connected) {
        final ping = AudioRelayProtocol.buildPing(
          DateTime.now().millisecondsSinceEpoch,
        );
        send(ping);
      }
    });
  }

  void _handleData(dynamic message) {
    if (message is List<int>) {
      _receiveBuffer.add(Uint8List.fromList(message));
      _processBuffer();
    }
  }

  void _processBuffer() {
    final allBytes = BytesBuilder();
    for (final chunk in _receiveBuffer) {
      allBytes.add(chunk);
    }
    final data = allBytes.toBytes();

    int offset = 0;
    while (offset + 4 <= data.length) {
      final length =
          (data[offset] << 24) |
          (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3];
      final totalLen = 4 + length;
      if (offset + totalLen > data.length) break;

      final message = data.sublist(offset + 4, offset + totalLen);
      _messageController.add(message);
      offset += totalLen;
    }

    _receiveBuffer.clear();
    if (offset < data.length) {
      _receiveBuffer.add(data.sublist(offset));
    }
  }

  void _handleDone() {
    _connected = false;
    _emitState(WebSocketState.disconnected);
  }

  void _emitState(WebSocketState state) {
    _stateController.add(state);
  }
}

/// WebSocket connection states.
enum WebSocketState {
  connecting,
  connected,
  disconnected,
  error,
}
