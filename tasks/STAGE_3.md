# STAGE 3 — 자동 검색과 페어링

## Codex 시작 프롬프트

```text
STAGE 1과 2의 스트리밍 경로를 변경하지 말고 STAGE 3 연결 UX만 구현한다.
고정 IP 의존성을 제거하고 자동 검색, PIN, 신뢰 기기, 재연결을 완성한다.
```

## 작업 순서

1. TV NSD 광고
2. Windows mDNS 탐색
3. capability 교환
4. TV 6자리 PIN 생성
5. PIN 만료 처리
6. PC PIN 입력
7. 신뢰 기기 토큰 저장
8. 신뢰 해제
9. 최근 TV
10. 한 번 클릭 재연결
11. IP 직접 입력 fallback
12. 트레이 빠른 연결
13. 잘못된 PIN/다른 PC 보안 테스트

## 완료 체크

- [ ] TV 자동 발견
- [ ] 최초 PIN 연결
- [ ] 이후 무PIN 재연결
- [ ] 신뢰 해제 가능
- [ ] 무단 연결 차단
- [ ] IP fallback
- [ ] 사용자 상태 문구 정리
