import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';
import '../models/server_info.dart';

/// Discovers AudioRelay servers on the local network via:
/// 1. mDNS/Bonjour service discovery
/// 2. UDP broadcast probe
class ServerDiscoverer {
  final List<ServerInfo> servers = [];
  bool _running = false;

  MDnsClient? _mdns;
  RawDatagramSocket? _broadcastSocket;
  StreamSubscription? _broadcastSub;
  Timer? _probeTimer;

  final _discoverController = StreamController<ServerInfo>.broadcast();
  Stream<ServerInfo> get onDiscover => _discoverController.stream;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    await Future.wait([
      _startMDns(),
      _startBroadcastProbe(),
    ]);
  }

  void stop() {
    _running = false;
    _mdns?.stop();
    _mdns = null;
    _probeTimer?.cancel();
    _broadcastSub?.cancel();
    _broadcastSocket?.close();
    _broadcastSocket = null;
    servers.clear();
  }

  // --- mDNS Discovery ---

  Future<void> _startMDns() async {
    try {
      _mdns = MDnsClient();
      await _mdns!.start();

      // Browse for _audiorelay._tcp service
      await for (final ptr in _mdns!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_audiorelay._tcp.local'),
      )) {
        final name = ptr.domainName;
        await _resolveMDnsService(name);
      }
    } catch (_) {
      // mDNS may not be available on all networks
    }
  }

  Future<void> _resolveMDnsService(String name) async {
    try {
      // Resolve SRV record
      await for (final srv in _mdns!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(name),
      )) {
        final host = srv.target;
        final port = srv.port;

        // Resolve A record
        await for (final ip in _mdns!.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(host),
        )) {
          final server = ServerInfo(
            id: '${ip.address.address}:$port',
            name: name.replaceAll('._audiorelay._tcp.local', ''),
            host: ip.address.address,
            port: port,
          );
          _addServer(server);
        }
      }
    } catch (_) {}
  }

  // --- UDP Broadcast Probe ---

  Future<void> _startBroadcastProbe() async {
    try {
      _broadcastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // random local port
      );
      _broadcastSocket!.broadcastEnabled = true;
      _broadcastSocket!.readEventsEnabled = true;

      _broadcastSub = _broadcastSocket!.listen(_handleBroadcastResponse);

      // Send initial probe
      _sendBroadcastProbe();

      // Periodic probes
      _probeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _sendBroadcastProbe();
      });
    } catch (_) {}
  }

  void _sendBroadcastProbe() {
    try {
      final probe = Uint8List.fromList('AudioRelay Discover'.codeUnits);
      _broadcastSocket?.send(
        probe,
        InternetAddress('255.255.255.255'),
        59200,
      );
    } catch (_) {}
  }

  void _handleBroadcastResponse(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    try {
      final datagram = _broadcastSocket?.receive();
      if (datagram == null) return;

      final data = String.fromCharCodes(datagram.data);
      final addr = datagram.address.address;

      if (data.contains('AudioRelay')) {
        final server = ServerInfo(
          id: '$addr:59200',
          name: 'AudioRelay Server',
          host: addr,
        );
        _addServer(server);
      }
    } catch (_) {}
  }

  void _addServer(ServerInfo server) {
    if (!servers.any((s) => s.id == server.id)) {
      servers.add(server);
      _discoverController.add(server);
    }
  }
}
