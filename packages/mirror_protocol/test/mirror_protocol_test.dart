import 'dart:typed_data';

import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:test/test.dart';

void main() {
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
    });
  });

  group('StreamStartRequest', () {
    test('encodes the STAGE 1 video-only profile', () {
      const request = StreamStartRequest(
        sessionId: 'session-1',
        sourceType: SourceType.display,
        sourceId: r'\\.\DISPLAY1',
        video: VideoProfile.stageOne720p30(),
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
      });
      expect(StreamStartRequest.fromJson(json).video.codec, VideoCodec.h264);
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
    test('encodes the STAGE 1 decoder configuration as fixed binary', () {
      const config = H264CodecConfig(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 4000,
      );

      final copy = H264CodecConfig.decode(config.encode());

      expect(copy.width, 1280);
      expect(copy.height, 720);
      expect(copy.fps, 30);
      expect(copy.bitrateKbps, 4000);
      expect(copy.annexB, isTrue);
      expect(copy.spsPpsInBand, isTrue);
    });

    test('rejects malformed codec config payloads', () {
      expect(
        () => H264CodecConfig.decode(Uint8List(4)),
        throwsFormatException,
      );

      final payload = H264CodecConfig(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 4000,
      ).encode();
      payload[0] = 0;

      expect(() => H264CodecConfig.decode(payload), throwsFormatException);
    });
  });

  group('VideoPacket', () {
    test('round-trips a length-prefixed Annex B access unit', () {
      final packet = VideoPacket(
        type: VideoPacketType.accessUnit,
        sequenceNumber: 42,
        ptsUs: 33333,
        flags: VideoPacketFlags.keyFrame,
        payload: Uint8List.fromList([0, 0, 0, 1, 0x65, 0x88]),
      );

      final copy = VideoPacket.decodeLengthPrefixed(
        packet.encodeLengthPrefixed(),
      );

      expect(copy.type, VideoPacketType.accessUnit);
      expect(copy.sequenceNumber, 42);
      expect(copy.ptsUs, 33333);
      expect(copy.isKeyFrame, isTrue);
      expect(copy.payload, [0, 0, 0, 1, 0x65, 0x88]);
    });

    test('round-trips a codec config packet', () {
      final config = const H264CodecConfig(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 4000,
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

      final wrongPayloadLength = Uint8List.fromList(packet)..[27] = 9;
      expect(
        () => VideoPacket.decodeLengthPrefixed(wrongPayloadLength),
        throwsFormatException,
      );
    });
  });
}
