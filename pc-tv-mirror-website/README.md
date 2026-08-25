# PC TV Mirror Website

Firebase Hosting용 정적 웹사이트 템플릿입니다.

## 포함 페이지
- `/` 앱 소개
- `/windows/` Windows Sender 다운로드
- `/tv/` Android TV Receiver 다운로드
- `/privacy/` 개인정보 처리방침

## 다운로드 링크 수정
`public/config.js`에서 다음 값만 변경하세요.

```js
window.PCMIRROR_CONFIG = {
  windowsDownloadUrl: "https://github.com/Jihunkim00/pc-tv-mirror-planning/releases/download/v.1.0/windows_sender.exe",
  tvDownloadUrl: "https://...",
  githubUrl: "https://github.com/Jihunkim00/pc-tv-mirror-planning",
  supportEmail: "jihun@thj-project.info"
};
```

## Firebase Hosting 배포
```bash
npm install -g firebase-tools
firebase login
firebase init hosting
firebase deploy --only hosting
```

`firebase init hosting` 시 public directory는 `public`로 지정하세요.
이미 제공된 `firebase.json`을 유지하려면 덮어쓰지 않도록 주의하세요.

## 개인정보 처리방침
현재 문구는 로컬 미러링 중심 MVP를 기준으로 작성되었습니다.
Analytics, Crashlytics, Sentry, 원격 로그 업로드, 클라우드 릴레이, 계정 기능 등을 추가하면 실제 구현에 맞춰 반드시 업데이트하세요.
