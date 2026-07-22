# 04. 연결 프로토콜과 모델

## 1. 서비스 광고

```text
Service type: _pctvmirror._tcp
Device name: Living Room TV
Protocol version: 1
Control port: dynamic
Capabilities: h264, 1080p60, audio, low_latency
```

## 2. 제어 메시지

필수 메시지:

```text
hello
capabilities
pair.request
pair.challenge
pair.confirm
pair.result
session.offer
session.answer
session.ice
stream.start
stream.stop
stream.pause
quality.set
privacy.ready
frame.rendered
stats.report
ping
pong
error
```

## 3. capability 예시

```json
{
  "type": "capabilities",
  "protocolVersion": 1,
  "deviceId": "tv-uuid",
  "deviceName": "Living Room TV",
  "videoCodecs": ["h264"],
  "maxWidth": 1920,
  "maxHeight": 1080,
  "maxFps": 60,
  "lowLatencyDecoder": true,
  "audio": true
}
```

## 4. 스트림 시작 예시

```json
{
  "type": "stream.start",
  "sessionId": "session-uuid",
  "sourceType": "display",
  "sourceId": "DISPLAY1",
  "video": {
    "codec": "h264",
    "width": 1920,
    "height": 1080,
    "fps": 60,
    "bitrateKbps": 12000
  },
  "audio": {
    "enabled": true,
    "mode": "tvOnly",
    "codec": "opus",
    "sampleRate": 48000,
    "channels": 2
  },
  "privacyScreen": true
}
```

## 5. 공용 enum

```dart
enum AudioOutputMode {
  tvOnly,
  pcAndTv,
  videoOnly,
}

enum SourceType {
  display,
  window,
}

enum MirrorSessionState {
  idle,
  discovering,
  pairing,
  connecting,
  negotiating,
  streaming,
  reconnecting,
  stopping,
  restoring,
  failed,
}
```

## 6. 통계 메시지

```json
{
  "type": "stats.report",
  "sessionId": "session-uuid",
  "timestamp": "2026-07-22T10:00:00Z",
  "video": {
    "width": 1920,
    "height": 1080,
    "fps": 59.8,
    "bitrateKbps": 11420,
    "droppedFrames": 8
  },
  "network": {
    "rttMs": 18,
    "packetLossPercent": 0.4,
    "jitterMs": 3
  },
  "audio": {
    "bufferMs": 40,
    "underruns": 0
  }
}
```

## 7. 오류 코드

```text
DISCOVERY_TIMEOUT
PAIRING_INVALID_PIN
PAIRING_EXPIRED
PAIRING_UNTRUSTED_DEVICE
CAPTURE_PERMISSION_DENIED
CAPTURE_SOURCE_GONE
ENCODER_NOT_AVAILABLE
DECODER_NOT_AVAILABLE
AUDIO_CAPTURE_FAILED
AUDIO_ROUTE_FAILED
WEBRTC_NEGOTIATION_FAILED
NETWORK_DISCONNECTED
PRIVACY_OVERLAY_FAILED
LOCAL_STATE_RESTORE_FAILED
```

오류 응답에는 사용자 문구와 개발용 상세 원인을 분리한다.
