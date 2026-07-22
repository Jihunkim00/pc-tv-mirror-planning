# 05. 테스트와 출시 계획

## 1. 테스트 계층

### 단위 테스트

- 상태 머신 전이
- 프로토콜 직렬화/역직렬화
- PIN 만료와 검증
- 신뢰 기기 저장
- 품질 프로필 계산
- 오디오 모드 상태 복구
- 프라이버시 활성 조건

### 통합 테스트

- Windows 캡처 시작/중지 반복
- WebRTC offer/answer/ICE
- TV 첫 프레임 ACK
- 네트워크 끊김과 재연결
- 오디오 장치 변경과 복구
- 앱 강제 종료 후 다음 실행 복구

### 장시간 테스트

- 30분 영상/오디오
- 2시간 출시 후보 스트리밍
- 100회 연결/해제 반복
- 20회 네트워크 강제 끊김
- 절전/복귀
- TV 앱 background/foreground 반복

## 2. 하드웨어 매트릭스

### Windows GPU

- Intel 내장 GPU
- AMD GPU
- NVIDIA GPU

### TV

- Chromecast with Google TV 또는 Google TV 기기
- Sony Android/Google TV
- TCL Android/Google TV
- Android TV 셋톱박스

### 네트워크

- 2.4GHz Wi-Fi
- 5GHz Wi-Fi
- PC Ethernet + TV Wi-Fi
- AP Isolation 활성 네트워크
- packet loss 및 지연 주입 환경

## 3. 안전 테스트

반드시 자동 또는 수동 체크리스트로 검증한다.

- TV 첫 프레임 전에 PC 화면이 검게 되지 않는다.
- TV 전원을 끄면 PC 화면이 돌아온다.
- 공유기를 끄면 PC 화면이 돌아온다.
- 앱을 강제 종료하면 watchdog이 화면을 복구한다.
- TV 전용 오디오 종료 후 기존 장치로 복구된다.
- 복구 실패 시 사용자가 명확한 안내를 받는다.
- 긴급 단축키가 네이티브 UI 정지 상태에서도 동작한다.

## 4. CI 권장

```text
Windows job
- flutter analyze
- flutter test
- C++ build
- native unit tests

Android job
- flutter analyze
- flutter test
- Android lint
- Kotlin unit tests
- debug AAB/APK build

Protocol job
- shared model tests
- schema compatibility tests
```

## 5. Android TV 출시 준비

- TV launcher 설정
- touchscreen not required
- leanback/TV feature 선언
- 리모컨 포커스 검증
- TV 배너 이미지
- AAB 생성
- 지원 ABI 검증
- 네이티브 라이브러리 호환성 검증
- 개인정보 처리방침
- 로컬 네트워크 권한 설명
- 실제 TV 스크린샷

## 6. Windows 출시 준비

- 설치 프로그램 또는 MSIX
- 코드 서명
- 방화벽 규칙 안내
- 자동 시작 옵션
- 가상 오디오 드라이버 서명과 설치/제거
- 앱 제거 시 오디오 장치 복구
- crash dump와 사용자 로그 내보내기
- 자동 업데이트 정책

## 7. 출시 전 최종 체크

- 기본 설정은 1080p30 또는 자동 품질
- 프라이버시 화면은 opt-in
- TV 전용 오디오는 지원 상태 확인 후 활성화
- DRM 우회 가능하다는 표현 금지
- 같은 Wi-Fi/LAN 전용임을 명시
- 연결 실패 해결 안내 제공
- 소리와 화면 원상복구 방법 제공
