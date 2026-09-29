// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get waitingForVideoFrames => 'Waiting for PC video frames';

  @override
  String get restartReceiver => 'Restart receiver';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get stopReceiver => 'Stop receiver';

  @override
  String get autoFullscreen => 'Auto fullscreen';

  @override
  String get fpsDebugOverlay => 'FPS debug overlay';

  @override
  String get actualCodecTiming => 'Actual codec render/display timing';

  @override
  String get fit => 'Fit';

  @override
  String get fill => 'Fill';

  @override
  String get controlPort => 'Control port';

  @override
  String get tvAddress => 'TV address';

  @override
  String get pcConnectionInfo => 'PC connection info';

  @override
  String get tvIpAddress => 'TV IP address';

  @override
  String get port => 'Port';

  @override
  String get ipAddressEntryInstruction => 'Enter this TV IP in the PC app.';

  @override
  String get ipAddressChecking => 'Checking IP address…';

  @override
  String get networkConnectionCheck => 'Check the network connection.';

  @override
  String get ipAddressLookupFailed =>
      'Couldn\'t check the IP address. Try again shortly.';

  @override
  String get protocol => 'Protocol';

  @override
  String get video => 'Video';

  @override
  String get fourK => '4K';

  @override
  String get decoder => 'Decoder';

  @override
  String get surface => 'Surface';

  @override
  String get performance => 'Performance';

  @override
  String get summary => 'Summary';

  @override
  String get receiveDecodePresent => 'Receive / Decode / Present';

  @override
  String get presentP95 => 'Present p95';

  @override
  String get latencyAvgP95 => 'Latency avg/p95';

  @override
  String get renderer => 'Renderer';

  @override
  String get queue => 'Queue';

  @override
  String get drops => 'Drops';

  @override
  String get sequenceGaps => 'Sequence gaps';

  @override
  String get audio => 'Audio';

  @override
  String get audioCodec => 'Codec';

  @override
  String get audioDecoder => 'Decoder';

  @override
  String get track => 'Track';

  @override
  String get audioSession => 'Audio session';

  @override
  String get queuePcm => 'Queue / PCM';

  @override
  String get buffered => 'Buffered';

  @override
  String get avSync => 'A/V sync';

  @override
  String get avAvgP95 => 'A/V avg/p95';

  @override
  String get audioPackets => 'Audio packets';

  @override
  String get audioWrites => 'Audio writes';

  @override
  String get audioRecovery => 'Audio recovery';

  @override
  String get audioReset => 'Audio reset';

  @override
  String get audioExpected => 'Audio expected';

  @override
  String get audioDrops => 'Audio drops';

  @override
  String get audioResetReason => 'Audio reset reason';

  @override
  String get audioError => 'Audio error';

  @override
  String get presentation => 'Presentation';

  @override
  String get autoEntered => 'Auto entered';

  @override
  String get userExited => 'User exited';

  @override
  String get playback => 'Playback';

  @override
  String get scaleMode => 'Scale mode';

  @override
  String get display => 'Display';

  @override
  String get videoView => 'Video view';

  @override
  String get aspectError => 'Aspect error';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get bytes => 'Bytes';

  @override
  String get config => 'Config';

  @override
  String get accessUnits => 'Access units';

  @override
  String get keyFrames => 'Key frames';

  @override
  String get decoderIo => 'Decoder input/output';

  @override
  String get releasedToSurface => 'Released to surface';

  @override
  String get codecCreateRelease => 'Codec create/release';

  @override
  String get surfaceLifecycle => 'Surface lifecycle';

  @override
  String get surfaceValid => 'Surface valid';

  @override
  String get surfaceSize => 'Surface size';

  @override
  String get surfaceZOrder => 'Surface z-order';

  @override
  String get configuredOutput => 'Configured/output';

  @override
  String get outputCrop => 'Output crop';

  @override
  String get lastError => 'Last error';

  @override
  String get receiverLog => 'Receiver log';

  @override
  String get state => 'State';

  @override
  String get idle => 'idle';

  @override
  String get checking => 'Checking';

  @override
  String get pending => 'Pending';

  @override
  String get mediaCodecReady => 'MediaCodec ready';

  @override
  String get surfaceViewReady => 'SurfaceView ready';

  @override
  String get receiverStarting => 'Receiver is starting.';

  @override
  String get receiverStartFailed => 'Receiver could not start.';

  @override
  String get receiverStopFailed => 'Receiver stop failed.';

  @override
  String get videoDebug => 'VIDEO DEBUG';

  @override
  String get renderMode => 'Render mode';

  @override
  String get releaseImmediateScheduled => 'Release immediate/scheduled';

  @override
  String get input => 'Input';

  @override
  String get codecRendered => 'Codec rendered';

  @override
  String get renderP50P95Max => 'Render p50/p95/max';

  @override
  String get jitterP95 => 'Jitter p95';

  @override
  String get gaps => 'Gaps';

  @override
  String get pts => 'PTS';

  @override
  String get drift => 'drift';

  @override
  String get mode => 'Mode';

  @override
  String get receiverStateReady => 'Ready';

  @override
  String get receiverStateStarting => 'Starting';

  @override
  String get receiverStateListening => 'Listening';

  @override
  String get receiverStateConnecting => 'Connecting';

  @override
  String get receiverStateNegotiating => 'Negotiating';

  @override
  String get receiverStateWaitingForSurface => 'Waiting for display';

  @override
  String get receiverStateWaitingForKeyFrame => 'Waiting for first frame';

  @override
  String get receiverStateStreaming => 'Streaming';

  @override
  String get receiverStatePaused => 'Paused';

  @override
  String get receiverStateResuming => 'Resuming';

  @override
  String get receiverStateDisconnected => 'Disconnected';

  @override
  String get receiverStateError => 'Error';

  @override
  String get receiverStateStopping => 'Stopping';

  @override
  String get receiverStateRestoring => 'Restoring';

  @override
  String get receiverStateFailed => 'Failed';

  @override
  String get statusReady => 'Receiver is ready for a PC.';

  @override
  String get statusStarting => 'Starting the receiver.';

  @override
  String get statusListening => 'Waiting for a PC connection.';

  @override
  String get statusConnecting => 'PC connected; preparing the session.';

  @override
  String get statusNegotiating => 'Negotiating the video stream.';

  @override
  String get statusWaitingForSurface => 'Waiting for the TV display surface.';

  @override
  String get statusWaitingForKeyFrame => 'Waiting for the first video frame.';

  @override
  String get statusStreaming => 'Receiving video from the PC.';

  @override
  String get statusPaused => 'Playback is paused.';

  @override
  String get statusResuming => 'Resuming playback.';

  @override
  String get statusStopping => 'Stopping the receiver session.';

  @override
  String get statusRestoring => 'Releasing receiver resources.';

  @override
  String get statusFailed =>
      'Receiver error. Check the receiver log for details.';
}
