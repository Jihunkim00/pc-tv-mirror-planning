// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get language => '언어';

  @override
  String get systemLanguage => '시스템 기본값';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => '日本語';

  @override
  String get monitorSource => '모니터 소스';

  @override
  String get noDisplays => '디스플레이를 찾을 수 없습니다.';

  @override
  String get betaVersion => '베타 버전';

  @override
  String get refreshDisplays => '디스플레이 새로 고침';

  @override
  String get copyDiagnostics => '진단 정보 복사';

  @override
  String get receiverIp => 'TV IP 주소';

  @override
  String get receiverIpExample => '예: 192.168.1.40';

  @override
  String get controlPort => '제어 포트';

  @override
  String get videoProfile => '영상 프로필';

  @override
  String get start => '시작';

  @override
  String get stop => '중지';

  @override
  String get sessionLog => '세션 로그';

  @override
  String get diagnosticsCopied => '진단 정보를 클립보드에 복사했습니다.';

  @override
  String get diagnosticsCopyFailed => '진단 정보를 복사하지 못했습니다.';

  @override
  String get invalidTvIpv4 => '올바른 TV IPv4 주소를 입력하세요.';

  @override
  String get pcSoundMute => 'PC 스피커 음소거';

  @override
  String get pcSoundMuteDescription =>
      '미러링 중에만 Windows 오디오 캡처 장치를 음소거합니다. TV 오디오 전송은 계속됩니다.';

  @override
  String get pcSoundMuteOff => 'PC 스피커 음소거가 꺼져 있습니다.';

  @override
  String get pcSoundMuteWaiting => '오디오 캡처가 시작되기를 기다리는 중입니다.';

  @override
  String get pcSoundMuteRestoring => 'Windows 오디오 음소거 상태를 복원하는 중입니다.';

  @override
  String get pcSoundMuteActive => 'Windows 오디오 캡처 장치가 음소거되었습니다.';

  @override
  String get pcSoundMuteAlreadyMuted => '미러링 전에 Windows가 이미 음소거 상태였습니다.';

  @override
  String get pcSoundMuteUserChanged =>
      'Windows에서 음소거 상태가 바뀌었습니다. 변경한 상태를 유지합니다.';

  @override
  String get pcSoundMuteEndpointUnavailable => '오디오 캡처 장치를 사용할 수 없습니다.';

  @override
  String get pcSoundMuteControlUnavailable =>
      'Windows에서 이 장치의 음소거 제어를 지원하지 않습니다.';

  @override
  String get pcSoundMuteApplyFailed => 'Windows 오디오 장치를 음소거하지 못했습니다.';

  @override
  String get pcSoundMuteRestoreFailed => '이전 Windows 음소거 상태를 복원하지 못했습니다.';

  @override
  String get pcSoundMuteCaptureFailed => '오디오 캡처가 중지되어 PC 스피커를 음소거하지 않았습니다.';

  @override
  String get pcSoundMuteOnlyDuringMirroring => 'PC 스피커 음소거는 미러링 중에만 적용됩니다.';

  @override
  String get fourKSelectDisplay => '이 프로필을 사용하려면 4K 디스플레이를 선택하세요.';

  @override
  String get fourKDisplayTooSmall => '선택한 캡처 디스플레이가 3840 x 2160보다 작습니다.';

  @override
  String get experimental => '실험 기능';

  @override
  String get profile720p30Hq => '720p30 고화질';

  @override
  String get profile1080p30Hq => '1080p30 고화질';

  @override
  String get profile1080p24Cinema => '1080p24 시네마';

  @override
  String get profile1080p60 => 'FHD 1080p60';

  @override
  String get profile720p30Compat => '720p30 호환';

  @override
  String get profile4k30 => '4K 30fps';

  @override
  String get profileDesc720p30Hq => '저지연 720p30 H.264';

  @override
  String get profileDesc1080p30Hq => '균형 잡힌 1080p30 H.264';

  @override
  String get profileDesc1080p24Cinema => '디스플레이 주기에 맞춘 FHD 24fps 시네마 H.264';

  @override
  String get profileDesc1080p60 => '14Mbps FHD 60fps 미러링 H.264 (실험 기능)';

  @override
  String get profileDesc720p30Compat => '낮은 비트레이트 720p30 H.264';

  @override
  String get profileDesc4k30 => '호환 하드웨어 인코더, Android TV 디코더, 유선 LAN이 필요합니다';

  @override
  String get stateReady => '준비됨';

  @override
  String get stateStarting => '시작 중';

  @override
  String get stateListening => 'TV 연결 대기 중';

  @override
  String get stateConnecting => '연결 중';

  @override
  String get stateNegotiating => '스트림 준비 중';

  @override
  String get stateWaitingForSurface => 'TV 화면 대기 중';

  @override
  String get stateWaitingForKeyFrame => '첫 프레임 대기 중';

  @override
  String get stateStreaming => '미러링 중';

  @override
  String get statePaused => '일시 중지';

  @override
  String get stateResuming => '재개 중';

  @override
  String get stateStopping => '중지 중';

  @override
  String get stateRestoring => '복원 중';

  @override
  String get stateFailed => '실패';

  @override
  String get statusReady => '디스플레이를 선택하고 TV 주소를 입력하세요.';

  @override
  String get statusStarting => 'Windows 화면 및 오디오 캡처를 준비하고 있습니다.';

  @override
  String get statusListening => 'TV 연결을 기다리고 있습니다.';

  @override
  String get statusConnecting => 'TV에 연결하고 있습니다.';

  @override
  String get statusNegotiating => '영상 스트림을 준비하고 있습니다.';

  @override
  String get statusWaitingForSurface => 'TV 화면이 준비되기를 기다리고 있습니다.';

  @override
  String get statusWaitingForKeyFrame => '첫 영상 프레임을 기다리고 있습니다.';

  @override
  String get statusStreaming => 'TV로 영상을 보내고 있습니다.';

  @override
  String get statusPaused => 'TV에서 재생을 일시 중지했습니다.';

  @override
  String get statusResuming => '영상 재생을 다시 시작하고 있습니다.';

  @override
  String get statusStopping => '미러링 세션을 중지하고 있습니다.';

  @override
  String get statusRestoring => '세션 리소스를 복원하고 있습니다.';

  @override
  String get statusFailed => '세션을 계속할 수 없습니다. 자세한 내용은 진단 정보를 확인하세요.';

  @override
  String get performance => '성능';

  @override
  String get capture => '캡처';

  @override
  String get profile => '프로필';

  @override
  String get fallback => '대체 설정';

  @override
  String get targetActual => '목표 / 실제';

  @override
  String get callback => '콜백';

  @override
  String get intervalP95 => '간격 p95';

  @override
  String get targetInterval => '목표 간격';

  @override
  String get replacedCadence => '대체 / 주기';

  @override
  String get queueDepth => '대기열 깊이';

  @override
  String get convertEncode => '변환 / 인코딩';

  @override
  String get admissionAccepted => '승인 / 수락';

  @override
  String get converted => '변환됨';

  @override
  String get encoderInput => '인코더 입력';

  @override
  String get encoded => '인코딩됨';

  @override
  String get convertPath => '변환 경로';

  @override
  String get encodeAvgP95 => '인코딩 평균/p95';

  @override
  String get encoder => '인코더';

  @override
  String get fourKCapability => '4K 지원';

  @override
  String get backpressure => '처리 지연';

  @override
  String get processInOutP95 => '처리 입력/출력 p95';

  @override
  String get readbackReuse => '읽기 복사 / 재사용';

  @override
  String get network => '네트워크';

  @override
  String get sent => '전송됨';

  @override
  String get sendIntervalP95 => '전송 간격 p95';

  @override
  String get sendDuration => '전송 시간';

  @override
  String get socketCalls => '소켓 호출';

  @override
  String get pending => '대기 중';

  @override
  String get queueWaitAvgP95 => '대기열 대기 평균/p95';

  @override
  String get staleVideoDrops => '오래된 영상 삭제';

  @override
  String get audio => '오디오';

  @override
  String get audioState => '상태';

  @override
  String get audioDevice => '장치';

  @override
  String get inputEncoded => '입력 / 인코딩';

  @override
  String get captureSent => '캡처 / 전송';

  @override
  String get encodeAverage => '인코딩 평균';

  @override
  String get queueDropped => '대기열 / 삭제';

  @override
  String get writerWaitVA => '작성 대기 영상/오디오';

  @override
  String get audioError => '오디오 오류';

  @override
  String get tvAudioPath => 'TV 오디오 경로';

  @override
  String get pcMuteRequested => 'PC 음소거 요청';

  @override
  String get pcMuteApplied => 'PC 음소거 적용';

  @override
  String get pcMuteActual => 'Windows 음소거 상태';

  @override
  String get pcMuteOriginal => '초기 음소거 상태';

  @override
  String get pcMuteExternalChange => 'Windows에서 변경됨';

  @override
  String get pcMuteTargetDevice => '음소거 대상 장치 ID';

  @override
  String get pcMuteErrorCode => '음소거 오류 코드';

  @override
  String get playbackControl => '재생 제어';

  @override
  String get pauseResume => '일시 중지 / 재개';

  @override
  String get ackError => 'ACK / 오류';

  @override
  String get resumeConfigResend => '재개 설정 재전송';

  @override
  String get capturedTotal => '전체 캡처';

  @override
  String get lastSequence => '마지막 시퀀스';

  @override
  String get intentionalSkip => '의도적 건너뜀';

  @override
  String get realDrops => '실제 삭제';

  @override
  String get configSent => '설정 전송';

  @override
  String get keyFrames => '키 프레임';

  @override
  String get totalDropped => '전체 삭제';

  @override
  String get packets => '패킷';

  @override
  String get bytes => '바이트';

  @override
  String get sendCompleted => '전송 완료';

  @override
  String get captureToEncode => '캡처 -> 인코딩';

  @override
  String get valueDisabled => '사용 안 함';

  @override
  String get valueUnknown => '알 수 없음';

  @override
  String get valueHardware => '하드웨어';

  @override
  String get valueSoftware => '소프트웨어';

  @override
  String get valueCapturing => '캡처 중';

  @override
  String get valueStarting => '시작 중';

  @override
  String get valueFailed => '실패';

  @override
  String get valueReadback => '읽기 복사';

  @override
  String get valueZeroCopy => '제로 카피';

  @override
  String get valueReuse => '재사용';

  @override
  String get valueAllocate => '할당';
}
