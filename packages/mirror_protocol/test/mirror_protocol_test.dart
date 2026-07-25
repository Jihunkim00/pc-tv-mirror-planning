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
        PerformanceProfile.highQuality1080p30,
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
        'bitrateKbps': 6000,
        'performanceProfile': 'lowLatency720p30',
      });
      expect(StreamStartRequest.fromJson(json).video.codec, VideoCodec.h264);
    });

    test('encodes the STAGE 4 selectable high-quality 1080p30 profile', () {
      const request = StreamStartRequest(
        sessionId: 'session-1080',
        sourceType: SourceType.display,
        sourceId: r'\\.\DISPLAY1',
        video: VideoProfile.highQuality1080p30(),
      );

      final json = request.toJson();
      final video = json['video'] as Map<String, Object?>;

      expect(video['width'], 1920);
      expect(video['height'], 1080);
      expect(video['fps'], 30);
      expect(video['bitrateKbps'], 9000);
      expect(video['performanceProfile'], 'highQuality1080p30');
      expect(
        StreamStartRequest.fromJson(json).video.performanceProfile,
        PerformanceProfile.highQuality1080p30,
      );
    });

    test('encodes the STAGE 3 system audio profile when requested', () {
      const request = StreamStartRequest(
        sessionId: 'session-1',
        sourceType: SourceType.display,
        sourceId: r'\\.\DISPLAY1',
        video: VideoProfile.lowLatency720p30(),
        audio: AudioProfile.systemAacLc(),
      );

      final json = request.toJson();
      final audio = json['audio'] as Map<String, Object?>;

      expect(audio, {
        'enabled': true,
        'codec': 'aacLc',
        'sampleRate': 48000,
        'channelCount': 2,
        'bitrate': 128000,
        'source': 'systemLoopback',
      });
      expect(StreamStartRequest.fromJson(json).audio?.codec, AudioCodec.aacLc);
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

  group('PlaybackCommand', () {
    test('round-trips receiver pause commands', () {
      const command = PlaybackCommand(
        sessionId: 'session-1',
        commandId: 15,
        command: PlaybackCommandKind.pause,
        receiverTimestampUs: 123456,
        reason: 'remote_key',
        requestedBy: 'receiver_remote',
      );

      final copy = PlaybackCommand.fromJson(command.toJson());

      expect(copy.sessionId, 'session-1');
      expect(copy.commandId, 15);
      expect(copy.command, PlaybackCommandKind.pause);
      expect(copy.receiverTimestampUs, 123456);
      expect(copy.requestedBy, 'receiver_remote');
    });

    test('round-trips sender ACK and error messages', () {
      const ack = PlaybackCommandAck(
        commandId: 16,
        command: PlaybackCommandKind.resume,
        senderState: 'resuming',
      );
      const error = PlaybackCommandError(
        commandId: 17,
        command: PlaybackCommandKind.pause,
        errorCode: 'INVALID_STATE',
        message: 'No active sender session.',
      );

      expect(
        PlaybackCommandAck.fromJson(ack.toJson()).senderState,
        'resuming',
      );
      expect(
        PlaybackCommandError.fromJson(error.toJson()).errorCode,
        'INVALID_STATE',
      );
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
      ).encode()..[23] = 0x40;

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
      },
    );

    test(
      'decodes legacy 24-byte packet headers without sequence or PTS crash',
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
      },
    );

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

    test('round-trips an AAC codec config packet', () {
      final config = AacCodecConfig(
        sampleRate: 48000,
        channelCount: 2,
        bitrate: 128000,
        streamStartPtsUs: 123456,
        codecSpecificData: Uint8List.fromList([0x11, 0x90]),
      ).encode();
      final packet = VideoPacket(
        type: VideoPacketType.audioConfig,
        sequenceNumber: 0,
        ptsUs: 123456,
        payload: config,
      );

      final copy = VideoPacket.decodeLengthPrefixed(
        packet.encodeLengthPrefixed(),
      );
      final decoded = AacCodecConfig.decode(copy.payload);

      expect(copy.type, VideoPacketType.audioConfig);
      expect(decoded.codec, 'audio/mp4a-latm');
      expect(decoded.sampleRate, 48000);
      expect(decoded.channelCount, 2);
      expect(decoded.bitrate, 128000);
      expect(decoded.streamStartPtsUs, 123456);
      expect(decoded.codecSpecificData, [0x11, 0x90]);
    });

    test('round-trips an AAC access unit with uint64 sequence and PTS', () {
      final packet = VideoPacket(
        type: VideoPacketType.audioAccessUnit,
        sequenceNumber: 0x100000055,
        ptsUs: 456789,
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      final copy = VideoPacket.decodeLengthPrefixed(
        packet.encodeLengthPrefixed(),
      );

      expect(copy.type, VideoPacketType.audioAccessUnit);
      expect(copy.sequenceNumber, 0x100000055);
      expect(copy.ptsUs, 456789);
      expect(copy.payload, [1, 2, 3, 4]);
    });

    test('rejects malformed audio payload lengths', () {
      final config = AacCodecConfig(
        sampleRate: 48000,
        channelCount: 2,
        bitrate: 128000,
        streamStartPtsUs: 1,
        codecSpecificData: Uint8List.fromList([0x11, 0x90]),
      ).encode();
      final packet = VideoPacket(
        type: VideoPacketType.audioConfig,
        sequenceNumber: 0,
        ptsUs: 1,
        payload: config,
      ).encodeLengthPrefixed();

      final wrongPayloadLength = Uint8List.fromList(packet)..[31] = 99;
      expect(
        () => VideoPacket.decodeLengthPrefixed(wrongPayloadLength),
        throwsFormatException,
      );

      expect(() => AacCodecConfig.decode(Uint8List(4)), throwsFormatException);
    });

    test('enforces audio packet payload limits', () {
      expect(AudioPacketLimits.configMaxPayloadLength, 64 * 1024);
      expect(AudioPacketLimits.accessUnitMaxPayloadLength, 256 * 1024);
      expect(
        () => VideoPacket(
          type: VideoPacketType.audioAccessUnit,
          sequenceNumber: 1,
          ptsUs: 1,
          payload: Uint8List(AudioPacketLimits.accessUnitMaxPayloadLength + 1),
        ).encodeLengthPrefixed(),
        throwsRangeError,
      );
    });

    test('parses interleaved video and audio packets', () {
      final video = VideoPacket(
        type: VideoPacketType.accessUnit,
        sequenceNumber: 7,
        ptsUs: 7000,
        payload: Uint8List.fromList([0, 0, 0, 1, 0x41]),
      );
      final audio = VideoPacket(
        type: VideoPacketType.audioAccessUnit,
        sequenceNumber: 8,
        ptsUs: 7100,
        payload: Uint8List.fromList([0x21, 0x22]),
      );

      final packets = [video, audio]
          .map(
            (packet) =>
                VideoPacket.decodeLengthPrefixed(packet.encodeLengthPrefixed()),
          )
          .toList();

      expect(packets.map((packet) => packet.type), [
        VideoPacketType.accessUnit,
        VideoPacketType.audioAccessUnit,
      ]);
      expect(packets[1].sequenceNumber, 8);
      expect(packets[1].ptsUs, 7100);
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
