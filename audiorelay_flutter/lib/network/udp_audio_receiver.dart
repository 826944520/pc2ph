import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'protocol/messages.dart';

/// UDP audio data receiver.
/// Listens on port 59100 for Opus-encoded audio packets from the PC server.
class UDPAudioReceiver {
  final int port;
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  bool _running = false;

  int _lastSeqNum = 0;
  int _totalPackets = 0;
  int _lostPackets = 0;
  String? lastError;

  final _packetController = StreamController<AudioPacket>.broadcast();
  final _stateController = StreamController<UDPState>.broadcast();

  Stream<AudioPacket> get packetStream => _packetController.stream;
  Stream<UDPState> get stateStream => _stateController.stream;
  bool get isRunning => _running;
  int get packetsReceived => _totalPackets;
  int get packetsLost => _lostPackets;

  UDPAudioReceiver({this.port = 59100});

  Future<void> start() async {
    if (_running) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
      );

      _socket!.readEventsEnabled = true;
      _running = true;
      _emitState(UDPState.listening);

      _subscription = _socket!.listen(_handlePacket);
    } catch (e) {
      lastError = e.toString();
      _emitState(UDPState.error);
    }
  }

  void stop() {
    _running = false;
    _subscription?.cancel();
    _socket?.close();
    _socket = null;
    _emitState(UDPState.stopped);
  }

  void _handlePacket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    try {
      final datagram = _socket?.receive();
      if (datagram == null) return;

      final packet = AudioPacket.parse(datagram.data);

      _totalPackets++;
      if (_lastSeqNum > 0 && packet.sequenceNumber > _lastSeqNum + 1) {
        _lostPackets += packet.sequenceNumber - _lastSeqNum - 1;
      }
      _lastSeqNum = packet.sequenceNumber;

      _packetController.add(packet);
    } catch (_) {
      // Skip malformed packets
    }
  }

  void _emitState(UDPState state) {
    _stateController.add(state);
  }
}

/// UDP receiver states.
enum UDPState {
  idle,
  listening,
  stopped,
  error,
}
