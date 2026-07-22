# 03. UI/UX 디자인 기준

참고 디자인 철학: https://github.com/emilkowalski/skills

## 1. 경험 목표

사용자가 느껴야 하는 감정은 `빠르다`, `안전하다`, `복잡하지 않다`다. 화려함보다 즉각적인 반응과 예측 가능한 상태를 우선한다.

## 2. Windows 화면 구조

### 기본 탐색

- 미러링
- 기기
- 기록
- 설정

### 미러링 첫 화면

1. 연결 가능한 TV
2. 화면 또는 창 선택
3. 화질 프리셋
4. 소리 출력
5. PC 화면 가리기
6. 연결 버튼

비트레이트, 코덱, 포트, 지연 조정은 고급 설정으로 이동한다.

## 3. TV 화면 구조

### 대기 화면

- 제품명
- 연결 대기 상태
- TV 이름
- 최초 연결 PIN
- 같은 Wi-Fi 안내
- 연결된 PC 관리

### 재생 화면

기본은 영상 전체 화면이다. 확인 또는 메뉴 버튼을 누르면 하단 컨트롤이 나타난다.

- 연결 해제
- 화면 맞춤
- 음량
- 연결 정보

## 4. 시각 기준

### 색상 역할

- Background: 매우 어두운 중립색
- Surface: 배경보다 한 단계 밝은 중립색
- Accent: 한 가지 블루 또는 청록 계열
- Success: 연결 완료
- Warning: 네트워크 불안정 또는 복구 중
- Error: 연결 실패

색상만으로 상태를 구분하지 않고 아이콘과 문구를 함께 사용한다.

### 재질

- glass/blur는 툴바와 임시 컨트롤에만 사용한다.
- 일반 카드에는 불투명 surface를 사용한다.
- 투명 레이어를 여러 겹 겹치지 않는다.
- 큰 패널일수록 더 높은 불투명도와 명확한 계층을 사용한다.

### 타이포그래피

- 시스템 폰트를 기본으로 사용한다.
- 큰 제목은 자간을 약간 좁게 한다.
- 본문은 충분한 line height를 제공한다.
- TV에서는 최소 글자 크기를 넉넉하게 잡는다.

## 5. 모션 토큰

```dart
abstract final class AppMotion {
  static const press = Duration(milliseconds: 120);
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 220);
  static const modal = Duration(milliseconds: 280);

  static const easeOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const easeInOut = Cubic(0.77, 0.0, 0.175, 1.0);

  static const pressedScale = 0.97;
  static const tvFocusedScale = 1.03;
}
```

## 6. 모션 규칙

- 300ms를 넘는 일반 UI 애니메이션을 만들지 않는다.
- 버튼은 pointer down/focus press 순간에 반응한다.
- 등장 요소를 `scale 0`에서 시작하지 않는다.
- enter는 ease-out, 위치 이동은 ease-in-out을 우선한다.
- 자주 쓰는 단축키는 애니메이션 없이 즉시 실행한다.
- 연결 상태 변화는 과도한 축하 효과보다 아이콘/텍스트 전환을 사용한다.
- 팝오버는 트리거에서 시작한다.
- 모달은 중앙 기준으로 나타난다.

## 7. TV 포커스

- 기본 scale: 1.00
- focus scale: 최대 1.03
- pressed scale: 약 0.98
- focus 시 테두리, 명도, 그림자를 함께 조정한다.
- 포커스가 사라지는 경로가 없어야 한다.
- 뒤로 버튼은 항상 이전 화면 또는 종료 확인으로 연결한다.

## 8. 접근성

- reduced motion: 이동/스프링 대신 짧은 fade
- reduced transparency: blur 제거와 불투명 배경
- high contrast: 명확한 테두리와 대비
- 키보드 및 TV 리모컨 focus indicator
- 오류는 색상, 아이콘, 제목, 해결 방법을 함께 표시

## 9. 상태 문구

| 내부 상태 | 사용자 문구 |
|---|---|
| discovering | TV를 찾고 있습니다 |
| pairing | TV 연결을 확인하는 중입니다 |
| connecting | 화면 전송을 준비하고 있습니다 |
| streaming | TV로 전송 중입니다 |
| degraded | 네트워크 상태가 불안정합니다 |
| reconnecting | TV에 다시 연결하고 있습니다 |
| restoring | PC 화면과 소리를 복구하고 있습니다 |
| failed | 연결하지 못했습니다 |
| stopped | 미러링이 종료되었습니다 |
