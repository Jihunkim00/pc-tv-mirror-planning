# STAGE 1 — 최소 영상 수직 기능

## Codex 시작 프롬프트

```text
AGENTS.md와 docs/00_PRODUCT_SPEC.md, docs/01_ARCHITECTURE.md,
docs/02_ROADMAP_5_STAGES.md를 먼저 읽어라.
현재는 STAGE 1만 구현한다. 오디오, 자동 검색, PIN, 프라이버시 화면은 구현하지 않는다.
작업을 작은 커밋 가능한 단위로 나누고, 각 단위마다 빌드와 테스트를 실행하라.
```

## 작업 순서

1. 모노레포 폴더 생성
2. Windows Flutter 앱 생성
3. Android TV Flutter 앱 생성
4. `mirror_protocol` 패키지 생성
5. Windows 네이티브 플러그인 skeleton
6. Android TV 네이티브 플러그인 skeleton
7. Windows 모니터 목록 조회
8. 화면 캡처 시작/중지
9. H.264 720p30 인코딩
10. 개발용 로컬 signaling
11. TV MediaCodec 디코딩
12. SurfaceView 출력
13. 연결 상태 UI
14. 10분 안정성 테스트

## 금지 사항

- Dart로 프레임 byte 전달
- 임시로 JPEG 연속 전송
- 오디오 선행 구현
- 프라이버시 오버레이 선행 구현

## 완료 체크

- [ ] Windows에서 모니터 선택 가능
- [ ] TV에서 실제 화면 표시
- [ ] 시작/중지 10회 반복 가능
- [ ] 10분 연속 실행
- [ ] 앱 종료 후 리소스 해제
- [ ] flutter analyze/test 통과
- [ ] 네이티브 빌드 통과
