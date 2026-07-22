# 01. 기술 아키텍처

## 1. 전체 구조

```text
Windows Sender
  Flutter UI
    ↓ platform channel / FFI
  C++/WinRT Native Engine
    ├─ Windows.Graphics.Capture
    ├─ D3D11 frame pipeline
    ├─ Media Foundation H.264 encoder
    ├─ WASAPI loopback capture
    ├─ optional virtual audio device
    ├─ WebRTC PeerConnection
    ├─ mDNS/DNS-SD discovery client
    └─ privacy overlay + watchdog
             ↓ LAN / WebRTC
Android TV Receiver
  Flutter TV UI
    ↓ platform channel
  Kotlin/C++ Native Receiver
    ├─ NSD service advertisement
    ├─ WebRTC receiver
    ├─ MediaCodec decoder
    ├─ SurfaceView renderer
    ├─ AudioTrack output
    └─ pairing/trust storage
```

## 2. 기술 선택

### Windows

- UI: Flutter Windows
- 네이티브: C++/WinRT
- 화면 캡처: Windows.Graphics.Capture
- GPU: Direct3D 11
- 영상 인코딩: Media Foundation H.264 하드웨어 인코더
- 시스템 오디오: WASAPI Loopback
- TV 전용 오디오: 가상 오디오 장치 또는 검증된 라우팅 모듈
- 전송: WebRTC Native
- 프라이버시 오버레이: 별도 HWND + 캡처 제외
- 배포: MSIX 또는 서명된 installer

### Android TV

- UI: Flutter Android TV
- 네이티브 브리지: Kotlin
- 영상 수신: WebRTC Native
- 디코딩: MediaCodec hardware decoder
- 출력: SurfaceView 또는 TextureView보다 SurfaceView 우선
- 오디오: AudioTrack/WebRTC audio sink
- 서비스 검색: Android NSD
- 배포: Android App Bundle

## 3. 권장 모노레포 구조

```text
pc-tv-mirror/
├─ AGENTS.md
├─ README.md
├─ apps/
│  ├─ windows_sender/
│  │  ├─ lib/
│  │  │  ├─ app/
│  │  │  ├─ core/
│  │  │  │  ├─ native_bridge/
│  │  │  │  ├─ logging/
│  │  │  │  └─ settings/
│  │  │  └─ features/
│  │  │     ├─ discovery/
│  │  │     ├─ pairing/
│  │  │     ├─ mirroring/
│  │  │     ├─ audio_output/
│  │  │     ├─ privacy_screen/
│  │  │     ├─ diagnostics/
│  │  │     └─ settings/
│  │  └─ windows/
│  │     └─ runner/native/
│  │        ├─ capture/
│  │        ├─ video/
│  │        ├─ audio/
│  │        ├─ transport/
│  │        ├─ discovery/
│  │        ├─ privacy/
│  │        └─ recovery/
│  └─ android_tv_receiver/
│     ├─ lib/
│     │  ├─ app/
│     │  ├─ core/
│     │  └─ features/
│     │     ├─ receiver/
│     │     ├─ pairing/
│     │     ├─ playback/
│     │     └─ settings/
│     └─ android/app/src/main/kotlin/.../
│        ├─ discovery/
│        ├─ receiver/
│        ├─ decoder/
│        ├─ audio/
│        └─ pairing/
├─ packages/
│  ├─ mirror_protocol/
│  ├─ shared_models/
│  └─ shared_ui/
├─ native/
│  ├─ windows_mirror_engine/
│  └─ android_tv_receiver_engine/
├─ docs/
├─ tasks/
├─ scripts/
└─ .github/workflows/
```

## 4. 핵심 네이티브 인터페이스

Flutter에는 원본 영상 프레임이 아니라 제어 명령과 상태만 전달한다.

```dart
abstract interface class MirrorNativeApi {
  Future<List<DisplayInfo>> listDisplays();
  Future<List<WindowInfo>> listWindows();
  Future<void> startSession(StartSessionRequest request);
  Future<void> stopSession();
  Future<void> setQuality(QualityProfile profile);
  Future<void> setAudioMode(AudioOutputMode mode);
  Stream<MirrorSessionEvent> watchEvents();
}
```

이벤트 예시:

```text
engineReady
receiverDiscovered
pairingRequired
connecting
firstFrameSent
firstFrameRendered
streaming
qualityChanged
reconnecting
restoringLocalState
stopped
error
```

## 5. 상태 머신

```text
idle
 → discovering
 → pairing
 → connecting
 → negotiating
 → streaming
 → reconnecting
 → stopping
 → restoring
 → idle
```

실패 시에는 가능한 상태에서 항상 `restoring`을 거쳐 `idle`로 이동한다.

## 6. 데이터 저장

초기에는 로컬 DB가 필수는 아니다. 다음 데이터는 안전한 로컬 저장소에 보관한다.

- 신뢰 TV ID와 공개키/토큰
- 마지막 연결 TV
- 기본 화질
- 오디오 모드
- 프라이버시 화면 설정
- 이전 Windows 오디오 출력 장치 ID
- 비정상 종료 복구 플래그

로그 파일에는 다음만 저장한다.

- 상태 전이
- 오류 코드
- 해상도/FPS/비트레이트
- RTT/packet loss
- 복구 실행 결과

PIN, 오디오 원본, 영상 원본, 개인 화면 캡처 이미지는 저장하지 않는다.
