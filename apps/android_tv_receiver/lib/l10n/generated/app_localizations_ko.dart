// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get waitingForVideoFrames => 'PC 영상 프레임 대기 중';

  @override
  String get restartReceiver => '수신기 다시 시작';

  @override
  String get fullscreen => '전체 화면';

  @override
  String get stopReceiver => '수신기 중지';

  @override
  String get autoFullscreen => '자동 전체 화면';

  @override
  String get fpsDebugOverlay => 'FPS 디버그 오버레이';

  @override
  String get actualCodecTiming => '실제 코덱 렌더링/표시 시간';

  @override
  String get fit => '맞춤';

  @override
  String get fill => '채우기';

  @override
  String get controlPort => '제어 포트';

  @override
  String get tvAddress => 'TV 주소';

  @override
  String get protocol => '프로토콜';

  @override
  String get video => '영상';

  @override
  String get fourK => '4K';

  @override
  String get decoder => '디코더';

  @override
  String get surface => 'Surface';

  @override
  String get performance => '성능';

  @override
  String get summary => '요약';

  @override
  String get receiveDecodePresent => '수신 / 디코딩 / 표시';

  @override
  String get presentP95 => '표시 p95';

  @override
  String get latencyAvgP95 => '지연 평균/p95';

  @override
  String get renderer => '렌더러';

  @override
  String get queue => '대기열';

  @override
  String get drops => '드롭';

  @override
  String get sequenceGaps => '시퀀스 누락';

  @override
  String get audio => '오디오';

  @override
  String get audioCodec => '코덱';

  @override
  String get audioDecoder => '디코더';

  @override
  String get track => '트랙';

  @override
  String get audioSession => '오디오 세션';

  @override
  String get queuePcm => '대기열 / PCM';

  @override
  String get buffered => '버퍼링';

  @override
  String get avSync => '오디오/영상 동기화';

  @override
  String get avAvgP95 => '오디오/영상 평균/p95';

  @override
  String get audioPackets => '오디오 패킷';

  @override
  String get audioWrites => '오디오 쓰기';

  @override
  String get audioRecovery => '오디오 복구';

  @override
  String get audioReset => '오디오 재설정';

  @override
  String get audioExpected => '오디오 예상 상태';

  @override
  String get audioDrops => '오디오 드롭';

  @override
  String get audioResetReason => '오디오 재설정 이유';

  @override
  String get audioError => '오디오 오류';

  @override
  String get presentation => '화면 표시';

  @override
  String get autoEntered => '자동 진입';

  @override
  String get userExited => '사용자 종료';

  @override
  String get playback => '재생';

  @override
  String get scaleMode => '크기 조정 방식';

  @override
  String get display => '디스플레이';

  @override
  String get videoView => '영상 보기';

  @override
  String get aspectError => '화면 비율 오차';

  @override
  String get diagnostics => '진단 정보';

  @override
  String get bytes => '바이트';

  @override
  String get config => '설정';

  @override
  String get accessUnits => '액세스 유닛';

  @override
  String get keyFrames => '키 프레임';

  @override
  String get decoderIo => '디코더 입력/출력';

  @override
  String get releasedToSurface => 'Surface 출력';

  @override
  String get codecCreateRelease => '코덱 생성/해제';

  @override
  String get surfaceLifecycle => 'Surface 수명 주기';

  @override
  String get surfaceValid => 'Surface 유효';

  @override
  String get surfaceSize => 'Surface 크기';

  @override
  String get surfaceZOrder => 'Surface z 순서';

  @override
  String get configuredOutput => '구성/출력';

  @override
  String get outputCrop => '출력 자르기';

  @override
  String get lastError => '마지막 오류';

  @override
  String get receiverLog => '수신기 로그';

  @override
  String get state => '상태';

  @override
  String get idle => '대기';

  @override
  String get checking => '확인 중';

  @override
  String get pending => '대기 중';

  @override
  String get mediaCodecReady => 'MediaCodec 준비됨';

  @override
  String get surfaceViewReady => 'SurfaceView 준비됨';

  @override
  String get receiverStarting => '수신기를 시작하고 있습니다.';

  @override
  String get receiverStartFailed => '수신기를 시작하지 못했습니다.';

  @override
  String get receiverStopFailed => '수신기 중지에 실패했습니다.';

  @override
  String get videoDebug => '영상 디버그';

  @override
  String get renderMode => '렌더링 방식';

  @override
  String get releaseImmediateScheduled => '즉시/예약 출력';

  @override
  String get input => '입력';

  @override
  String get codecRendered => '코덱 렌더링';

  @override
  String get renderP50P95Max => '렌더링 p50/p95/max';

  @override
  String get jitterP95 => '지터 p95';

  @override
  String get gaps => '누락';

  @override
  String get pts => 'PTS';

  @override
  String get drift => '편차';

  @override
  String get mode => '모드';

  @override
  String get receiverStateReady => '준비됨';

  @override
  String get receiverStateStarting => '시작 중';

  @override
  String get receiverStateListening => '연결 대기 중';

  @override
  String get receiverStateConnecting => '연결 중';

  @override
  String get receiverStateNegotiating => '협상 중';

  @override
  String get receiverStateWaitingForSurface => '화면 대기 중';

  @override
  String get receiverStateWaitingForKeyFrame => '첫 프레임 대기 중';

  @override
  String get receiverStateStreaming => '전송 중';

  @override
  String get receiverStatePaused => '일시 중지';

  @override
  String get receiverStateResuming => '재개 중';

  @override
  String get receiverStateDisconnected => '연결 끊김';

  @override
  String get receiverStateError => '오류';

  @override
  String get receiverStateStopping => '중지 중';

  @override
  String get receiverStateRestoring => '복원 중';

  @override
  String get receiverStateFailed => '실패';

  @override
  String get statusReady => '수신기가 준비되었습니다. PC 연결을 기다립니다.';

  @override
  String get statusStarting => '수신기를 시작하고 있습니다.';

  @override
  String get statusListening => 'PC 연결을 기다리고 있습니다.';

  @override
  String get statusConnecting => 'PC가 연결되어 세션을 준비하고 있습니다.';

  @override
  String get statusNegotiating => '영상 스트림을 협상하고 있습니다.';

  @override
  String get statusWaitingForSurface => 'TV 화면이 준비되기를 기다리고 있습니다.';

  @override
  String get statusWaitingForKeyFrame => '첫 영상 프레임을 기다리고 있습니다.';

  @override
  String get statusStreaming => 'PC에서 영상을 받고 있습니다.';

  @override
  String get statusPaused => '재생이 일시 중지되었습니다.';

  @override
  String get statusResuming => '재생을 다시 시작하고 있습니다.';

  @override
  String get statusStopping => '수신 세션을 중지하고 있습니다.';

  @override
  String get statusRestoring => '수신기 리소스를 정리하고 있습니다.';

  @override
  String get statusFailed => '수신기 오류가 발생했습니다. 자세한 내용은 수신기 로그를 확인하세요.';
}
