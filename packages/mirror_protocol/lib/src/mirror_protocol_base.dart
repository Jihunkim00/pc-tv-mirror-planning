import 'dart:typed_data';

const int mirrorProtocolVersion = 1;

enum SourceType {
  display('display');

  const SourceType(this.wireName);

  final String wireName;

  static SourceType fromWireName(String value) {
    return switch (value) {
      'display' => SourceType.display,
      _ => throw FormatException('Unsupported source type: $value'),
    };
  }
}

enum VideoCodec {
  h264('h264');

  const VideoCodec(this.wireName);

  final String wireName;

  static VideoCodec fromWireName(String value) {
    return switch (value) {
      'h264' => VideoCodec.h264,
      _ => throw FormatException('Unsupported video codec: $value'),
    };
  }
}

enum VideoPacketType {
  codecConfig(1),
  accessUnit(2),
  endOfStream(3);

  const VideoPacketType(this.wireValue);

  final int wireValue;

  static VideoPacketType fromWireValue(int value) {
    return switch (value) {
      1 => VideoPacketType.codecConfig,
      2 => VideoPacketType.accessUnit,
      3 => VideoPacketType.endOfStream,
      _ => throw FormatException('Unsupported video packet type: $value'),
    };
  }
}

abstract final class VideoPacketFlags {
  static const int none = 0;
  static const int keyFrame = 1 << 0;
  static const int codecConfig = 1 << 1;
}

enum MirrorSessionState {
  idle('idle'),
  starting('starting'),
  listening('listening'),
  connecting('connecting'),
  negotiating('negotiating'),
  waitingForSurface('waitingForSurface'),
  waitingForKeyFrame('waitingForKeyFrame'),
  streaming('streaming'),
  stopping('stopping'),
  restoring('restoring'),
  failed('failed');

  const MirrorSessionState(this.wireName);

  final String wireName;

  static MirrorSessionState fromWireName(String value) {
    return switch (value) {
      'idle' => MirrorSessionState.idle,
      'starting' => MirrorSessionState.starting,
      'listening' => MirrorSessionState.listening,
      'connecting' => MirrorSessionState.connecting,
      'negotiating' => MirrorSessionState.negotiating,
      'waitingForSurface' => MirrorSessionState.waitingForSurface,
      'waitingForKeyFrame' => MirrorSessionState.waitingForKeyFrame,
      'streaming' => MirrorSessionState.streaming,
      'stopping' => MirrorSessionState.stopping,
      'restoring' => MirrorSessionState.restoring,
      'failed' => MirrorSessionState.failed,
      _ => throw FormatException('Unsupported session state: $value'),
    };
  }
}

enum MirrorErrorCode {
  capturePermissionDenied('CAPTURE_PERMISSION_DENIED'),
  captureSourceGone('CAPTURE_SOURCE_GONE'),
  encoderNotAvailable('ENCODER_NOT_AVAILABLE'),
  decoderNotAvailable('DECODER_NOT_AVAILABLE'),
  signalingFailed('SIGNALING_FAILED'),
  networkDisconnected('NETWORK_DISCONNECTED'),
  invalidMessage('INVALID_MESSAGE');

  const MirrorErrorCode(this.wireName);

  final String wireName;

  static MirrorErrorCode fromWireName(String value) {
    return switch (value) {
      'CAPTURE_PERMISSION_DENIED' => MirrorErrorCode.capturePermissionDenied,
      'CAPTURE_SOURCE_GONE' => MirrorErrorCode.captureSourceGone,
      'ENCODER_NOT_AVAILABLE' => MirrorErrorCode.encoderNotAvailable,
      'DECODER_NOT_AVAILABLE' => MirrorErrorCode.decoderNotAvailable,
      'SIGNALING_FAILED' => MirrorErrorCode.signalingFailed,
      'NETWORK_DISCONNECTED' => MirrorErrorCode.networkDisconnected,
      'INVALID_MESSAGE' => MirrorErrorCode.invalidMessage,
      _ => throw FormatException('Unsupported error code: $value'),
    };
  }
}

final class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    required this.scaleFactor,
    required this.isPrimary,
  });

  final String id;
  final String name;
  final int width;
  final int height;
  final int x;
  final int y;
  final double scaleFactor;
  final bool isPrimary;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'width': width,
      'height': height,
      'x': x,
      'y': y,
      'scaleFactor': scaleFactor,
      'isPrimary': isPrimary,
    };
  }

  factory DisplayInfo.fromJson(Map<String, Object?> json) {
    return DisplayInfo(
      id: _readString(json, 'id'),
      name: _readString(json, 'name'),
      width: _readInt(json, 'width'),
      height: _readInt(json, 'height'),
      x: _readInt(json, 'x'),
      y: _readInt(json, 'y'),
      scaleFactor: _readNumber(json, 'scaleFactor').toDouble(),
      isPrimary: _readBool(json, 'isPrimary'),
    );
  }
}

final class ReceiverCapabilities {
  const ReceiverCapabilities({
    required this.deviceId,
    required this.deviceName,
    required this.videoCodecs,
    required this.maxWidth,
    required this.maxHeight,
    required this.maxFps,
    required this.lowLatencyDecoder,
    this.protocolVersion = mirrorProtocolVersion,
  });

  final int protocolVersion;
  final String deviceId;
  final String deviceName;
  final List<VideoCodec> videoCodecs;
  final int maxWidth;
  final int maxHeight;
  final int maxFps;
  final bool lowLatencyDecoder;

  Map<String, Object?> toJson() {
    return {
      'type': 'capabilities',
      'protocolVersion': protocolVersion,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'videoCodecs': videoCodecs.map((codec) => codec.wireName).toList(),
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'maxFps': maxFps,
      'lowLatencyDecoder': lowLatencyDecoder,
    };
  }

  factory ReceiverCapabilities.fromJson(Map<String, Object?> json) {
    _ensureType(json, 'capabilities');
    _ensureProtocolVersion(json);
    return ReceiverCapabilities(
      deviceId: _readString(json, 'deviceId'),
      deviceName: _readString(json, 'deviceName'),
      videoCodecs: _readStringList(
        json,
        'videoCodecs',
      ).map(VideoCodec.fromWireName).toList(growable: false),
      maxWidth: _readInt(json, 'maxWidth'),
      maxHeight: _readInt(json, 'maxHeight'),
      maxFps: _readInt(json, 'maxFps'),
      lowLatencyDecoder: _readBool(json, 'lowLatencyDecoder'),
    );
  }
}

final class VideoProfile {
  const VideoProfile({
    required this.codec,
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateKbps,
  });

  const VideoProfile.stageOne720p30()
      : codec = VideoCodec.h264,
        width = 1280,
        height = 720,
        fps = 30,
        bitrateKbps = 4000;

  final VideoCodec codec;
  final int width;
  final int height;
  final int fps;
  final int bitrateKbps;

  Map<String, Object?> toJson() {
    return {
      'codec': codec.wireName,
      'width': width,
      'height': height,
      'fps': fps,
      'bitrateKbps': bitrateKbps,
    };
  }

  factory VideoProfile.fromJson(Map<String, Object?> json) {
    return VideoProfile(
      codec: VideoCodec.fromWireName(_readString(json, 'codec')),
      width: _readInt(json, 'width'),
      height: _readInt(json, 'height'),
      fps: _readInt(json, 'fps'),
      bitrateKbps: _readInt(json, 'bitrateKbps'),
    );
  }
}

final class H264CodecConfig {
  H264CodecConfig({
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateKbps,
    required Uint8List sps,
    required Uint8List pps,
    this.annexB = true,
    this.spsPpsInBand = true,
  })  : sps = Uint8List.fromList(sps),
        pps = Uint8List.fromList(pps);

  static const int binaryHeaderLength = 24;
  static const int binaryLength = binaryHeaderLength;
  static const int _magic = 0x48323634; // H264

  final int width;
  final int height;
  final int fps;
  final int bitrateKbps;
  final Uint8List sps;
  final Uint8List pps;
  final bool annexB;
  final bool spsPpsInBand;

  Uint8List encode() {
    _checkRange('width', width, 16, 3840);
    _checkRange('height', height, 16, 2160);
    _checkRange('fps', fps, 1, 60);
    _checkUint32('bitrateKbps', bitrateKbps);
    _checkParameterSet('sps', sps, expectedNalType: 7);
    _checkParameterSet('pps', pps, expectedNalType: 8);

    final payloadLength = binaryHeaderLength + sps.length + pps.length;
    _checkPayloadLength(payloadLength);
    final bytes = Uint8List(payloadLength);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, _magic);
    data.setUint8(4, mirrorProtocolVersion);
    data.setUint8(5, (annexB ? 1 : 0) | (spsPpsInBand ? 2 : 0));
    data.setUint16(6, 0);
    data.setUint16(8, width);
    data.setUint16(10, height);
    data.setUint16(12, fps);
    data.setUint16(14, 0);
    data.setUint32(16, bitrateKbps);
    data.setUint16(20, sps.length);
    data.setUint16(22, pps.length);
    bytes.setRange(binaryHeaderLength, binaryHeaderLength + sps.length, sps);
    bytes.setRange(binaryHeaderLength + sps.length, bytes.length, pps);
    return bytes;
  }

  factory H264CodecConfig.decode(Uint8List bytes) {
    if (bytes.length < binaryHeaderLength) {
      throw FormatException('Invalid H.264 config length: ${bytes.length}');
    }

    final data = ByteData.sublistView(bytes);
    final magic = data.getUint32(0);
    if (magic != _magic) {
      throw FormatException('Invalid H.264 config magic: $magic');
    }

    final version = data.getUint8(4);
    if (version != mirrorProtocolVersion) {
      throw FormatException('Unsupported H.264 config version: $version');
    }

    final flags = data.getUint8(5);
    if ((flags & ~0x03) != 0) {
      throw FormatException('Unsupported H.264 config flags: $flags');
    }
    final spsLength = data.getUint16(20);
    final ppsLength = data.getUint16(22);
    final expectedLength = binaryHeaderLength + spsLength + ppsLength;
    if (bytes.length != expectedLength) {
      throw FormatException(
        'H.264 config SPS/PPS lengths do not match payload length: '
        '$spsLength/$ppsLength in ${bytes.length}',
      );
    }
    final sps = Uint8List.sublistView(
      bytes,
      binaryHeaderLength,
      binaryHeaderLength + spsLength,
    );
    final pps = Uint8List.sublistView(
      bytes,
      binaryHeaderLength + spsLength,
      expectedLength,
    );
    _checkParameterSet('sps', sps, expectedNalType: 7);
    _checkParameterSet('pps', pps, expectedNalType: 8);

    return H264CodecConfig(
      width: _checkedDecodedRange('width', data.getUint16(8), 16, 3840),
      height: _checkedDecodedRange('height', data.getUint16(10), 16, 2160),
      fps: _checkedDecodedRange('fps', data.getUint16(12), 1, 60),
      bitrateKbps: data.getUint32(16),
      sps: sps,
      pps: pps,
      annexB: (flags & 1) != 0,
      spsPpsInBand: (flags & 2) != 0,
    );
  }
}

final class VideoPacket {
  const VideoPacket({
    required this.type,
    required this.sequenceNumber,
    required this.ptsUs,
    required this.payload,
    this.flags = VideoPacketFlags.none,
  });

  static const int headerLength = 24;
  static const int lengthPrefixLength = 4;
  static const int maxPayloadLength = 8 * 1024 * 1024;
  static const int _magic = 0x5054564D; // PTVM

  final VideoPacketType type;
  final int flags;
  final int sequenceNumber;
  final int ptsUs;
  final Uint8List payload;

  bool get isKeyFrame => (flags & VideoPacketFlags.keyFrame) != 0;

  Uint8List encodeLengthPrefixed() {
    _checkUint16('flags', flags);
    _checkUint32('sequenceNumber', sequenceNumber);
    _checkUint64('ptsUs', ptsUs);
    _checkPayloadLength(payload.length);

    final packetLength = headerLength + payload.length;
    final bytes = Uint8List(lengthPrefixLength + packetLength);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, packetLength);
    data.setUint32(4, _magic);
    data.setUint8(8, mirrorProtocolVersion);
    data.setUint8(9, type.wireValue);
    data.setUint16(10, flags);
    data.setUint64(12, ptsUs);
    data.setUint32(20, sequenceNumber);
    data.setUint32(24, payload.length);
    bytes.setRange(lengthPrefixLength + headerLength, bytes.length, payload);
    return bytes;
  }

  factory VideoPacket.decodeLengthPrefixed(Uint8List bytes) {
    if (bytes.length < lengthPrefixLength + headerLength) {
      throw FormatException('Video packet is too short: ${bytes.length}');
    }

    final data = ByteData.sublistView(bytes);
    final packetLength = data.getUint32(0);
    if (packetLength < headerLength) {
      throw FormatException('Invalid video packet length: $packetLength');
    }
    if (packetLength > headerLength + maxPayloadLength) {
      throw FormatException('Video packet is larger than the configured limit');
    }
    if (bytes.length != lengthPrefixLength + packetLength) {
      throw FormatException(
        'Length prefix does not match buffer size: $packetLength',
      );
    }

    final magic = data.getUint32(4);
    if (magic != _magic) {
      throw FormatException('Invalid video packet magic: $magic');
    }

    final version = data.getUint8(8);
    if (version != mirrorProtocolVersion) {
      throw FormatException('Unsupported video packet version: $version');
    }

    final payloadLength = data.getUint32(24);
    if (payloadLength != packetLength - headerLength) {
      throw FormatException(
        'Payload length does not match packet length: $payloadLength',
      );
    }

    return VideoPacket(
      type: VideoPacketType.fromWireValue(data.getUint8(9)),
      flags: data.getUint16(10),
      ptsUs: data.getUint64(12),
      sequenceNumber: data.getUint32(20),
      payload: Uint8List.sublistView(bytes, lengthPrefixLength + headerLength),
    );
  }
}

final class StreamStartRequest {
  const StreamStartRequest({
    required this.sessionId,
    required this.sourceType,
    required this.sourceId,
    required this.video,
    this.protocolVersion = mirrorProtocolVersion,
  });

  final int protocolVersion;
  final String sessionId;
  final SourceType sourceType;
  final String sourceId;
  final VideoProfile video;

  Map<String, Object?> toJson() {
    return {
      'type': 'stream.start',
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
      'sourceType': sourceType.wireName,
      'sourceId': sourceId,
      'video': video.toJson(),
    };
  }

  factory StreamStartRequest.fromJson(Map<String, Object?> json) {
    _ensureType(json, 'stream.start');
    _ensureProtocolVersion(json);
    return StreamStartRequest(
      sessionId: _readString(json, 'sessionId'),
      sourceType: SourceType.fromWireName(_readString(json, 'sourceType')),
      sourceId: _readString(json, 'sourceId'),
      video: VideoProfile.fromJson(_readMap(json, 'video')),
    );
  }
}

final class StreamStopRequest {
  const StreamStopRequest({
    required this.sessionId,
    this.protocolVersion = mirrorProtocolVersion,
  });

  final int protocolVersion;
  final String sessionId;

  Map<String, Object?> toJson() {
    return {
      'type': 'stream.stop',
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
    };
  }

  factory StreamStopRequest.fromJson(Map<String, Object?> json) {
    _ensureType(json, 'stream.stop');
    _ensureProtocolVersion(json);
    return StreamStopRequest(sessionId: _readString(json, 'sessionId'));
  }
}

final class SessionEvent {
  const SessionEvent({
    required this.state,
    required this.userMessage,
    this.errorCode,
    this.developerMessage,
    this.protocolVersion = mirrorProtocolVersion,
  });

  final int protocolVersion;
  final MirrorSessionState state;
  final String userMessage;
  final MirrorErrorCode? errorCode;
  final String? developerMessage;

  Map<String, Object?> toJson() {
    return {
      'type': 'session.event',
      'protocolVersion': protocolVersion,
      'state': state.wireName,
      'userMessage': userMessage,
      if (errorCode != null) 'errorCode': errorCode!.wireName,
      if (developerMessage != null) 'developerMessage': developerMessage,
    };
  }

  factory SessionEvent.fromJson(Map<String, Object?> json) {
    _ensureType(json, 'session.event');
    _ensureProtocolVersion(json);
    final errorCode = json['errorCode'];
    return SessionEvent(
      state: MirrorSessionState.fromWireName(_readString(json, 'state')),
      userMessage: _readString(json, 'userMessage'),
      errorCode: errorCode == null
          ? null
          : MirrorErrorCode.fromWireName(_readString(json, 'errorCode')),
      developerMessage: json['developerMessage'] as String?,
    );
  }
}

final class VideoStats {
  const VideoStats({
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateKbps,
    required this.droppedFrames,
  });

  final int width;
  final int height;
  final double fps;
  final int bitrateKbps;
  final int droppedFrames;

  Map<String, Object?> toJson() {
    return {
      'width': width,
      'height': height,
      'fps': fps,
      'bitrateKbps': bitrateKbps,
      'droppedFrames': droppedFrames,
    };
  }

  factory VideoStats.fromJson(Map<String, Object?> json) {
    return VideoStats(
      width: _readInt(json, 'width'),
      height: _readInt(json, 'height'),
      fps: _readNumber(json, 'fps').toDouble(),
      bitrateKbps: _readInt(json, 'bitrateKbps'),
      droppedFrames: _readInt(json, 'droppedFrames'),
    );
  }
}

final class NetworkStats {
  const NetworkStats({
    required this.rttMs,
    required this.packetLossPercent,
    required this.jitterMs,
  });

  final int rttMs;
  final double packetLossPercent;
  final int jitterMs;

  Map<String, Object?> toJson() {
    return {
      'rttMs': rttMs,
      'packetLossPercent': packetLossPercent,
      'jitterMs': jitterMs,
    };
  }

  factory NetworkStats.fromJson(Map<String, Object?> json) {
    return NetworkStats(
      rttMs: _readInt(json, 'rttMs'),
      packetLossPercent: _readNumber(json, 'packetLossPercent').toDouble(),
      jitterMs: _readInt(json, 'jitterMs'),
    );
  }
}

final class StatsReport {
  const StatsReport({
    required this.sessionId,
    required this.timestamp,
    required this.video,
    required this.network,
    this.protocolVersion = mirrorProtocolVersion,
  });

  final int protocolVersion;
  final String sessionId;
  final DateTime timestamp;
  final VideoStats video;
  final NetworkStats network;

  Map<String, Object?> toJson() {
    return {
      'type': 'stats.report',
      'protocolVersion': protocolVersion,
      'sessionId': sessionId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'video': video.toJson(),
      'network': network.toJson(),
    };
  }

  factory StatsReport.fromJson(Map<String, Object?> json) {
    _ensureType(json, 'stats.report');
    _ensureProtocolVersion(json);
    return StatsReport(
      sessionId: _readString(json, 'sessionId'),
      timestamp: DateTime.parse(_readString(json, 'timestamp')).toUtc(),
      video: VideoStats.fromJson(_readMap(json, 'video')),
      network: NetworkStats.fromJson(_readMap(json, 'network')),
    );
  }
}

void _ensureType(Map<String, Object?> json, String expected) {
  final actual = json['type'];
  if (actual != expected) {
    throw FormatException('Expected message type $expected, got $actual');
  }
}

void _ensureProtocolVersion(Map<String, Object?> json) {
  final version = json['protocolVersion'];
  if (version != mirrorProtocolVersion) {
    throw FormatException('Unsupported protocol version: $version');
  }
}

void _checkUint16(String label, int value) {
  if (value < 0 || value > 0xFFFF) {
    throw RangeError.range(value, 0, 0xFFFF, label);
  }
}

void _checkRange(String label, int value, int min, int max) {
  if (value < min || value > max) {
    throw RangeError.range(value, min, max, label);
  }
}

int _checkedDecodedRange(String label, int value, int min, int max) {
  if (value < min || value > max) {
    throw FormatException('$label is outside the supported range: $value');
  }
  return value;
}

void _checkUint32(String label, int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw RangeError.range(value, 0, 0xFFFFFFFF, label);
  }
}

void _checkUint64(String label, int value) {
  if (value < 0) {
    throw RangeError.range(value, 0, null, label);
  }
}

void _checkPayloadLength(int length) {
  if (length < 0 || length > VideoPacket.maxPayloadLength) {
    throw RangeError.range(length, 0, VideoPacket.maxPayloadLength, 'payload');
  }
}

void _checkParameterSet(
  String label,
  Uint8List bytes, {
  required int expectedNalType,
}) {
  _checkUint16('$label.length', bytes.length);
  if (bytes.isEmpty) {
    throw FormatException('H.264 $label is empty');
  }
  final nalType = _h264NalType(bytes);
  if (nalType != expectedNalType) {
    throw FormatException(
      'H.264 $label has NAL type $nalType, expected $expectedNalType',
    );
  }
}

int _h264NalType(Uint8List bytes) {
  var offset = 0;
  if (bytes.length >= 4 &&
      bytes[0] == 0 &&
      bytes[1] == 0 &&
      bytes[2] == 0 &&
      bytes[3] == 1) {
    offset = 4;
  } else if (bytes.length >= 3 &&
      bytes[0] == 0 &&
      bytes[1] == 0 &&
      bytes[2] == 1) {
    offset = 3;
  }
  if (offset >= bytes.length) {
    throw const FormatException('H.264 NAL unit is missing a header byte');
  }
  return bytes[offset] & 0x1F;
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string for $key');
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected int for $key');
}

num _readNumber(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) {
    return value;
  }
  throw FormatException('Expected number for $key');
}

bool _readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool for $key');
}

List<String> _readStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  throw FormatException('Expected string list for $key');
}

Map<String, Object?> _readMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw FormatException('Expected object for $key');
}
