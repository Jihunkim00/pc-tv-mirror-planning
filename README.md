# PC TV Mirror 개발 마스터 계획

Windows 10/11 PC의 화면과 시스템 소리를 같은 Wi-Fi에 연결된 Android TV/Google TV로 전송하는 로컬 미러링 제품의 개발 기준 문서다.

이 패키지는 VS Code와 Codex에서 단계별로 개발하기 위한 기준 문서다. **한 번에 모든 기능을 구현하지 않고, `tasks/STAGE_1.md`부터 순서대로 진행한다.**

## 최종 제품 목표

- Windows 전체 화면, 특정 모니터 또는 특정 앱 창을 Android TV로 전송한다.
- 같은 Wi-Fi 안에서 TV를 자동 검색하고, 최초 1회 PIN 인증 후 한 번 클릭으로 재연결한다.
- 1080p 60fps 저지연 영상과 PC 시스템 소리를 TV에서 재생한다.
- 오디오 모드는 `TV에서만`, `PC와 TV 모두`, `화면만 전송`을 제공한다.
- 프라이버시 스크린을 켜면 TV에는 원래 화면이 보이지만 PC 모니터에는 검은 화면이 표시된다.
- TV 연결이 끊기거나 앱이 비정상 종료되면 PC 화면과 오디오 설정을 반드시 원상복구한다.
- Android TV 앱은 Google Play의 TV 앱 형태로 배포하고, Windows 앱은 서명된 설치 프로그램 또는 MSIX로 배포한다.

## 문서 순서

1. `AGENTS.md` — Codex가 반드시 지켜야 할 프로젝트 규칙
2. `docs/00_PRODUCT_SPEC.md` — 제품 기능과 범위
3. `docs/01_ARCHITECTURE.md` — 기술 구조와 폴더 구조
4. `docs/02_ROADMAP_5_STAGES.md` — 전체 5단계 로드맵
5. `docs/03_UI_UX_GUIDELINES.md` — 디자인 및 애니메이션 기준
6. `docs/04_PROTOCOL_AND_MODELS.md` — 연결 프로토콜과 데이터 모델
7. `docs/05_TEST_RELEASE.md` — 테스트, 보안, 스토어 출시 기준
8. `tasks/STAGE_1.md` ~ `tasks/STAGE_5.md` — 단계별 실제 작업 지시서

## 권장 개발 방식

- IDE: VS Code
- AI 코딩: Codex
- 버전 관리: Git + GitHub
- 작업 단위: 단계별 브랜치와 PR
- 브랜치 예시: `feat/stage-1-video-vertical-slice`
- PR은 한 단계의 완료 조건을 모두 통과한 뒤 병합한다.
- 다음 단계 기능을 미리 섞어 구현하지 않는다.

## 5단계 요약

| 단계 | 핵심 결과 |
|---|---|
| 1 | Windows 화면이 Android TV에 720p30으로 보이는 최소 수직 기능 완성 |
| 2 | WebRTC 기반 1080p60 영상, 시스템 오디오, A/V 동기화 완성 |
| 3 | 같은 Wi-Fi 자동 검색, PIN 페어링, 신뢰 기기, 한 번 클릭 재연결 완성 |
| 4 | TV 전용 오디오, 프라이버시 검은 화면, 장애 시 자동 복구 완성 |
| 5 | 적응형 화질, UI 완성도, 테스트, 스토어 배포 준비 완료 |

## 개발 시작 명령 예시

```powershell
mkdir pc-tv-mirror
cd pc-tv-mirror
git init
flutter create --platforms=windows apps/windows_sender
flutter create --platforms=android apps/android_tv_receiver
code .
```

그 후 이 패키지의 `AGENTS.md`, `docs`, `tasks` 폴더를 프로젝트 루트에 복사한다.

## 중요한 제품 제한

- DRM 또는 캡처 보호 화면을 우회하지 않는다.
- 최초 출시에서 인터넷 원격 스트리밍은 지원하지 않는다. LAN 전용이다.
- 최초 출시에서 키보드·마우스 원격 제어는 지원하지 않는다.
- 프라이버시 스크린은 실제 모니터 전원을 끄거나 디스플레이 장치를 비활성화하지 않는다.
- 영상 프레임을 Dart 메모리로 왕복 복사하지 않는다.
