import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:audiorelay_client/network/protocol/messages.dart';
import 'package:audiorelay_client/models/server_info.dart';
import 'package:audiorelay_client/models/connection_state.dart';

void main() {
  group('Protobuf encoding/decoding', () {
    test('ClientHello roundtrip', () {
      final encoded = AudioRelayProtocol.buildClientHello(
        clientId: 'test-id',
        clientVersion: '0.27.5',
        os: 'Flutter',
        osVersion: '1.0.0',
      );

      expect(encoded, isNotEmpty);
      expect(encoded.length, greaterThan(10));
    });

    test('Ping message encoding', () {
      final ping = AudioRelayProtocol.buildPing(1234567890);

      expect(ping, isNotEmpty);
      // Should be a small message (tag + varint timestamp)
      expect(ping.length, lessThan(10));
    });

    test('Frame message', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final framed = AudioRelayProtocol.frameMessage(payload);

      // 4-byte length prefix + payload
      expect(framed.length, equals(9));
      expect(framed[0], equals(0)); // length byte 1
      expect(framed[1], equals(0)); // length byte 2
      expect(framed[2], equals(0)); // length byte 3
      expect(framed[3], equals(5)); // length byte 4 = 5
    });

    test('AudioPacket parse', () {
      // Build a valid StreamData protobuf message
      final writer = ProtobufWriter();
      writer.writeInt64(1, 100); // tick
      writer.writeInt64(2, 1234567890); // timestamp_ms
      writer.writeBytes(3, Uint8List.fromList([0xAA, 0xBB, 0xCC])); // audio_data
      writer.writeBool(4, false); // is_retransmission
      writer.writeInt32(5, 42); // sequence_number
      final raw = writer.toBytes();

      final packet = AudioPacket.parse(raw);

      expect(packet.tick, equals(100));
      expect(packet.timestamp, equals(1234567890));
      expect(packet.data, equals([0xAA, 0xBB, 0xCC]));
      expect(packet.isRetransmission, isFalse);
      expect(packet.sequenceNumber, equals(42));
    });

    test('ProtobufReader skip unknown fields', () {
      final writer = ProtobufWriter();
      writer.writeInt32(99, 999); // unknown field
      writer.writeInt64(1, 42); // known field
      final raw = writer.toBytes();

      final packet = AudioPacket.parse(raw);

      // Should skip field 99 and parse field 1
      expect(packet.tick, equals(42));
      expect(packet.sequenceNumber, equals(0)); // default
    });
  });

  group('Models', () {
    test('ServerInfo equality', () {
      final s1 = ServerInfo(
        id: '1',
        name: 'Test',
        host: '192.168.1.1',
      );
      final s2 = ServerInfo(
        id: '1',
        name: 'Different',
        host: '10.0.0.1',
      );

      expect(s1, equals(s2)); // Same ID = same server
    });

    test('ServerInfo fromJson', () {
      final json = {
        'host': '192.168.1.100',
        'port': 59200,
        'audioPort': 59100,
      };

      final server = ServerInfo.fromJson(json);

      expect(server.host, equals('192.168.1.100'));
      expect(server.port, equals(59200));
      expect(server.audioPort, equals(59100));
    });
  });

  group('ConnectionState', () {
    test('ConnectionState values', () {
      expect(ConnectionState.values.length, equals(7));
      expect(ConnectionState.disconnected, equals(ConnectionState.disconnected));
      expect(ConnectionState.streaming, isNot(equals(ConnectionState.disconnected)));
    });
  });
}
