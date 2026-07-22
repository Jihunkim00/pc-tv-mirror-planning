# STAGE 2 — 고화질 영상과 시스템 오디오

## Codex 시작 프롬프트

```text
STAGE 1 완료 상태를 유지하고 STAGE 2만 구현한다.
WebRTC, 1080p, 시스템 오디오와 A/V sync에 집중한다.
TV 전용 오디오와 프라이버시 화면은 아직 구현하지 않는다.
```

## 작업 순서

1. signaling을 정리하고 WebRTC PeerConnection 적용
2. D3D11 프레임 파이프라인 정리
3. H.264 하드웨어 인코더 capability 탐지
4. 1080p30 프로필
5. 1080p60 프로필
6. WASAPI loopback 캡처
7. Opus 전송
8. TV 오디오 출력
9. PC+TV 동시 오디오
10. 화면만 전송 모드
11. A/V sync 측정
12. stats 표시
13. 30분 안정성 테스트

## 완료 체크

- [ ] 1080p30 30분 안정
- [ ] 지원 장치 1080p60
- [ ] TV 시스템 오디오 출력
- [ ] 화면만 모드 동작
- [ ] stats 수집
- [ ] 연결 종료 후 캡처/오디오 해제
