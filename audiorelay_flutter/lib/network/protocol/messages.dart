import 'dart:typed_data';

/// AudioRelay Protocol Buffer wire format helpers.
///
/// The protocol uses protocol buffers (lite runtime) for message
/// serialization over WebSocket (control) and UDP (audio data).
///
/// WebSocket framing: 4-byte big-endian length prefix + protobuf payload.
class AudioRelayProtocol {
  static const int tcpPort = 59200;
  static const int udpPort = 59100;
  static const int lengthPrefixSize = 4;

  /// Frame a protobuf message with 4-byte length prefix.
  static Uint8List frameMessage(Uint8List data) {
    final framed = Uint8List(lengthPrefixSize + data.length);
    final length = data.length;
    framed[0] = (length >> 24) & 0xFF;
    framed[1] = (length >> 16) & 0xFF;
    framed[2] = (length >> 8) & 0xFF;
    framed[3] = length & 0xFF;
    framed.setRange(lengthPrefixSize, framed.length, data);
    return framed;
  }

  /// Build a ClientHello protobuf message.
  static Uint8List buildClientHello({
    required String clientId,
    required String clientVersion,
    required String os,
    required String osVersion,
  }) {
    final buf = ProtobufWriter();
    buf.writeString(1, clientId);
    buf.writeString(2, clientVersion);
    buf.writeString(3, os);
    buf.writeString(4, osVersion);
    return buf.toBytes();
  }

  /// Build a Ping message.
  static Uint8List buildPing(int timestampMs) {
    final buf = ProtobufWriter();
    buf.writeInt64(1, timestampMs);
    return buf.toBytes();
  }
}

/// Minimal Protobuf wire-format encoder.
class ProtobufWriter {
  final List<int> _buffer = [];

  void writeVarint(int value) {
    var v = value;
    while (v > 127) {
      _buffer.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    _buffer.add(v & 0x7F);
  }

  void _writeTag(int fieldNumber, int wireType) {
    writeVarint((fieldNumber << 3) | wireType);
  }

  void writeString(int fieldNumber, String value) {
    final bytes = value.codeUnits;
    _writeTag(fieldNumber, 2); // wire_type 2 = length-delimited
    writeVarint(bytes.length);
    _buffer.addAll(bytes);
  }

  void writeBytes(int fieldNumber, Uint8List value) {
    _writeTag(fieldNumber, 2);
    writeVarint(value.length);
    _buffer.addAll(value);
  }

  void writeInt32(int fieldNumber, int value) {
    _writeTag(fieldNumber, 0); // wire_type 0 = varint
    writeVarint(value);
  }

  void writeInt64(int fieldNumber, int value) {
    _writeTag(fieldNumber, 0);
    writeVarint(value);
  }

  void writeBool(int fieldNumber, bool value) {
    _writeTag(fieldNumber, 0);
    _buffer.add(value ? 1 : 0);
  }

  Uint8List toBytes() => Uint8List.fromList(_buffer);
}

/// Minimal Protobuf wire-format decoder.
class ProtobufReader {
  final Uint8List _data;
  int _offset = 0;

  ProtobufReader(this._data);

  bool get isDone => _offset >= _data.length;

  /// Read next field tag. Returns (fieldNumber, wireType) or null if done.
  (int, int)? readTag() {
    if (isDone) return null;
    final raw = readVarint();
    return (raw >> 3, raw & 0x07);
  }

  int readVarint() {
    int result = 0;
    int shift = 0;
    while (_offset < _data.length) {
      final byte = _data[_offset++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw FormatException('Malformed varint');
  }

  int readInt64() => readVarint();
  int readInt32() => readVarint();
  bool readBool() => readVarint() != 0;

  Uint8List readBytes() {
    final length = readVarint();
    final end = _offset + length;
    if (end > _data.length) throw FormatException('Truncated bytes field');
    final result = _data.sublist(_offset, end);
    _offset = end;
    return result;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0: // varint
        readVarint();
        return;
      case 1: // 64-bit
        _offset += 8;
        return;
      case 2: // length-delimited
        _offset += readVarint();
        return;
      case 5: // 32-bit
        _offset += 4;
        return;
      default:
        throw FormatException('Unknown wire type: $wireType');
    }
  }
}

/// Parsed audio packet from UDP stream.
class AudioPacket {
  final int sequenceNumber;
  final int timestamp;
  final int tick;
  final bool isRetransmission;
  final Uint8List data;

  const AudioPacket({
    required this.sequenceNumber,
    required this.timestamp,
    required this.tick,
    required this.isRetransmission,
    required this.data,
  });

  /// Parse StreamData protobuf from raw UDP bytes.
  static AudioPacket parse(Uint8List raw) {
    var tick = 0;
    var timestampMs = 0;
    var audioData = Uint8List(0);
    var isRetrans = false;
    var seqNum = 0;

    final reader = ProtobufReader(raw);
    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag == null) break;
      final (fieldNumber, wireType) = tag;
      switch (fieldNumber) {
        case 1: // tick
          tick = reader.readInt64();
          break;
        case 2: // timestamp_ms
          timestampMs = reader.readInt64();
          break;
        case 3: // audio_data
          audioData = reader.readBytes();
          break;
        case 4: // is_retransmission
          isRetrans = reader.readBool();
          break;
        case 5: // sequence_number
          seqNum = reader.readInt32();
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return AudioPacket(
      sequenceNumber: seqNum,
      timestamp: timestampMs,
      tick: tick,
      isRetransmission: isRetrans,
      data: audioData,
    );
  }
}
