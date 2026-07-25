import 'dart:typed_data';

import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:test/test.dart';

final _sps = Uint8List.fromList([0, 0, 0, 1, 0x67, 0x42, 0x00, 0x1F]);
final _pps = Uint8List.fromList([0, 0, 0, 1, 0x68, 0xCE, 0x06, 0xE2]);

void main() {
  group('MirrorSessionState', () {
    test('parses STAGE 1 receiver lifecycle states', () {
      expect(
        MirrorSessionState.fromWireName('listening'),
        MirrorSessionState.listening,
      );
      expect(
        MirrorSessionState.fromWireName('waitingForSurface'),
        MirrorSessionState.waitingForSurface,
      );
      expect(
        MirrorSessionState.fromWireName('waitingForKeyFrame'),
        MirrorSessionState.waitingForKeyFrame,
      );
    });
  });

  group('ReceiverCapabilities', () {
    test('round-trips versioned H.264 decoder capabilities', () {
      const capabilities = ReceiverCapabilities(
        deviceId: 'tv-dev-1',
        deviceName: 'Development TV',
        videoCodecs: [VideoCodec.h264],
        maxWidth: 1280,
        maxHeight: 720,
        maxFps: 30,
        lowLatencyDecoder: true,
      );

      final copy = ReceiverCapabilities.fromJson(capabilities.toJson());

      expect(copy.protocolVersion, mirrorProtocolVersion);
      expect(copy.deviceId, capabilities.deviceId);
      expect(copy.videoCodecs, [VideoCodec.h264]);
      expect(copy.lowLatencyDecoder, isTrue);
      expect(copy.supportedPerformanceProfiles, [
        PerformanceProfile.lowLatency720p30,
        PerformanceProfile.compatibility720p30,
      ]);
    });
  });

  group('StreamStartRequest', () {
    test('encodes the STAGE 2 low-latency 720p30 video-only profile', () {
      const request = StreamStartRequest(
        sessionId: 'session-1',
        sourceType: SourceType.display,
        sourceId: r'\\.\DISPLAY1',
        video: VideoProfile.lowLatency720p30(),
      );

      final json = request.toJson();

      expect(json['type'], 'stream.start');
      expect(json.containsKey('audio'), isFalse);
      expect(json.containsKey('privacyScreen'), isFalse);
      expect(json['video'], {
        'codec': 'h264',
        'width': 1280,
        'height': 720,
        'fps': 30,
        'bitrateKbps': 4000,
        'performanceProfile': 'lowLatency720p30',
      });
      expect(StreamStartRequest.fromJson(json).video.codec, VideoCodec.h264);
    });

    test('keeps STAGE 1 profile alias backward-compatible', () {
      const profile = VideoProfile.stageOne720p30();

      expect(profile.performanceProfile, PerformanceProfile.lowLatency720p30);
      expect(profile.bitrateKbps, 4000);
    });

    test('rejects incompatible protocol versions', () {
      const request = StreamStartRequest(
        sessionId: 'session-1',
        sourceType: SourceType.display,
        sourceId: 'DISPLAY1',
        video: VideoProfile.stageOne720p30(),
      );
      final json = request.toJson()..['protocolVersion'] = 99;

      expect(() => StreamStartRequest.fromJson(json), throwsFormatException);
    });
  });

  group('StatsReport', () {
    test('round-trips video and network counters', () {
      final report = StatsReport(
        sessionId: 'session-1',
        timestamp: DateTime.utc(2026, 7, 22, 10),
        video: const VideoStats(
          width: 1280,
          height: 720,
          fps: 29.9,
          bitrateKbps: 3900,
          droppedFrames: 2,
        ),
        network: const NetworkStats(
          rttMs: 12,
          packetLossPercent: 0.1,
          jitterMs: 3,
        ),
      );

      final copy = StatsReport.fromJson(report.toJson());

      expect(copy.timestamp, DateTime.utc(2026, 7, 22, 10));
      expect(copy.video.fps, 29.9);
      expect(copy.network.packetLossPercent, 0.1);
    });
  });

  group('H264CodecConfig', () {
    test('encodes the STAGE 1 decoder configuration with SPS/PPS', () {
      final config = H264CodecConfig(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 4000,
        sps: _sps,
        pps: _pps,
      );

      final copy = H264CodecConfig.decode(config.encode());

      expect(copy.width, 1280);
      expect(copy.height, 720);
      expect(copy.fps, 30);
      expect(copy.bitrateKbps, 4000);
      expect(copy.annexB, isTrue);
      expect(copy.spsPpsInBand, isTrue);
      expect(copy.sps, _sps);
      expect(copy.pps, _pps);
    });

    test('rejects malformed codec config payloads', () {
      expect(() => H264CodecConfig.decode(Uint8List(4)), throwsFormatException);

      final payload = H264CodecConfig(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 4000,
        sps: _sps,
        pps: _pps,
      ).encode();
      payload[0] = 0;

      expect(() => H264CodecConfig.decode(payload), throwsFormatException);

      final wrongLength = H264CodecConfig(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 4000,
        sps: _sps,
        pps: _pps,
      ).encode()
        ..[23] = 0x40;

      expect(() => H264CodecConfig.decode(wrongLength), throwsFormatException);

      expect(
        () => H264CodecConfig(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateKbps: 4000,
          sps: Uint8List.fromList([0, 0, 0, 1, 0x65]),
          pps: _pps,
        ).encode(),
        throwsFormatException,
      );

      expect(
        () => H264CodecConfig(
          width: 8,
          height: 720,
          fps: 30,
          bitrateKbps: 4000,
          sps: _sps,
          pps: _pps,
        ).encode(),
        throwsRangeError,
      );
    });
  });

  group('VideoPacket', () {
    test(
        'round-trips a length-prefixed Annex B access unit with uint64 sequence',
        () {
      final packet = VideoPacket(
        type: VideoPacketType.accessUnit,
        sequenceNumber: 0x10000002A,
        ptsUs: 33333,
        flags: VideoPacketFlags.keyFrame,
        payload: Uint8List.fromList([0, 0, 0, 1, 0x65, 0x88]),
      );

      final copy = VideoPacket.decodeLengthPrefixed(
        packet.encodeLengthPrefixed(),
      );

      expect(copy.type, VideoPacketType.accessUnit);
      expect(copy.sequenceNumber, 0x10000002A);
      expect(copy.ptsUs, 33333);
      expect(copy.isKeyFrame, isTrue);
      expect(copy.flags & VideoPacketFlags.extendedHeader, isNonZero);
      expect(copy.payload, [0, 0, 0, 1, 0x65, 0x88]);
    });

    test('decodes legacy 24-byte packet headers without sequence or PTS crash',
        () {
      final legacy = _legacyAccessUnitPacket(
        sequenceNumber: 42,
        ptsUs: 33333,
        flags: VideoPacketFlags.keyFrame,
        payload: Uint8List.fromList([0, 0, 0, 1, 0x65]),
      );

      final copy = VideoPacket.decodeLengthPrefixed(legacy);

      expect(copy.sequenceNumber, 42);
      expect(copy.ptsUs, 33333);
      expect(copy.isKeyFrame, isTrue);
      expect(copy.flags & VideoPacketFlags.extendedHeader, 0);
    });

    test('round-trips a codec config packet', () {
      final config = H264CodecConfig(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 4000,
        sps: _sps,
        pps: _pps,
      ).encode();
      final packet = VideoPacket(
        type: VideoPacketType.codecConfig,
        sequenceNumber: 0,
        ptsUs: 0,
        flags: VideoPacketFlags.codecConfig,
        payload: config,
      );

      final copy = VideoPacket.decodeLengthPrefixed(
        packet.encodeLengthPrefixed(),
      );

      expect(copy.type, VideoPacketType.codecConfig);
      expect(H264CodecConfig.decode(copy.payload).width, 1280);
    });

    test('rejects malformed packet lengths and headers', () {
      final packet = VideoPacket(
        type: VideoPacketType.accessUnit,
        sequenceNumber: 1,
        ptsUs: 1,
        payload: Uint8List.fromList([1, 2, 3]),
      ).encodeLengthPrefixed();

      expect(
        () => VideoPacket.decodeLengthPrefixed(Uint8List(8)),
        throwsFormatException,
      );

      final wrongLength = Uint8List.fromList(packet)..[3] = packet[3] + 1;
      expect(
        () => VideoPacket.decodeLengthPrefixed(wrongLength),
        throwsFormatException,
      );

      final wrongMagic = Uint8List.fromList(packet)..[4] = 0;
      expect(
        () => VideoPacket.decodeLengthPrefixed(wrongMagic),
        throwsFormatException,
      );

      final wrongPayloadLength = Uint8List.fromList(packet)..[31] = 9;
      expect(
        () => VideoPacket.decodeLengthPrefixed(wrongPayloadLength),
        throwsFormatException,
      );
    });

    test('enforces the 8MB STAGE 1 access unit limit', () {
      expect(VideoPacket.maxPayloadLength, 8 * 1024 * 1024);
      expect(
        () => VideoPacket(
          type: VideoPacketType.accessUnit,
          sequenceNumber: 1,
          ptsUs: 1,
          payload: Uint8List(VideoPacket.maxPayloadLength + 1),
        ).encodeLengthPrefixed(),
        throwsRangeError,
      );

      final oversizedLength = Uint8List(
        VideoPacket.lengthPrefixLength + VideoPacket.headerLength,
      );
      final data = ByteData.sublistView(oversizedLength);
      data.setUint32(
        0,
        VideoPacket.headerLength + VideoPacket.maxPayloadLength + 1,
      );
      expect(
        () => VideoPacket.decodeLengthPrefixed(oversizedLength),
        throwsFormatException,
      );
    });
  });
}

Uint8List _legacyAccessUnitPacket({
  required int sequenceNumber,
  required int ptsUs,
  required int flags,
  required Uint8List payload,
}) {
  final packetLength = VideoPacket.legacyHeaderLength + payload.length;
  final bytes = Uint8List(VideoPacket.lengthPrefixLength + packetLength);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, packetLength);
  data.setUint32(4, 0x5054564D);
  data.setUint8(8, mirrorProtocolVersion);
  data.setUint8(9, VideoPacketType.accessUnit.wireValue);
  data.setUint16(10, flags);
  data.setUint64(12, ptsUs);
  data.setUint32(20, sequenceNumber);
  data.setUint32(24, payload.length);
  bytes.setRange(
    VideoPacket.lengthPrefixLength + VideoPacket.legacyHeaderLength,
    bytes.length,
    payload,
  );
  return bytes;
}
