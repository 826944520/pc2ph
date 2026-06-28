/// Information about a discovered AudioRelay server.
class ServerInfo {
  final String id;
  final String name;
  final String host;
  final int port;
  final int audioPort;
  final String version;
  final List<String> features;
  final String? osVersion;

  const ServerInfo({
    required this.id,
    required this.name,
    required this.host,
    this.port = 59200,
    this.audioPort = 59100,
    this.version = '0.27.5',
    this.features = const [],
    this.osVersion,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      id: json['id'] as String? ?? '${json['host']}:${json['port']}',
      name: json['name'] as String? ?? 'AudioRelay Server',
      host: json['host'] as String? ?? 'unknown',
      port: json['port'] as int? ?? 59200,
      audioPort: json['audioPort'] as int? ?? 59100,
      version: json['version'] as String? ?? '0.27.5',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServerInfo && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Audio format configuration.
class AudioFormat {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int bitrate;

  const AudioFormat({
    this.sampleRate = 48000,
    this.channels = 2,
    this.bitsPerSample = 16,
    this.bitrate = 96000,
  });
}

/// Network statistics.
class NetworkStats {
  int bytesReceived = 0;
  int packetsReceived = 0;
  int packetsLost = 0;
  double averageLatency = 0;
  double maxLatency = 0;
  int underflowCount = 0;
  bool hasOutOfOrderPackets = false;
}
