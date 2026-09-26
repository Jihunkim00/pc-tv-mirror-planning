// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get language => 'Language';

  @override
  String get systemLanguage => 'System default';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => '日本語';

  @override
  String get monitorSource => 'Monitor source';

  @override
  String get noDisplays => 'No displays found.';

  @override
  String get betaVersion => 'Beta version';

  @override
  String get refreshDisplays => 'Refresh displays';

  @override
  String get copyDiagnostics => 'Copy diagnostics';

  @override
  String get receiverIp => 'TV IP address';

  @override
  String get receiverIpExample => 'Example: 192.168.1.40';

  @override
  String get controlPort => 'Control port';

  @override
  String get videoProfile => 'Video profile';

  @override
  String get start => 'Start';

  @override
  String get stop => 'Stop';

  @override
  String get sessionLog => 'Session log';

  @override
  String get diagnosticsCopied => 'Diagnostics copied to clipboard.';

  @override
  String get diagnosticsCopyFailed => 'Could not copy diagnostics.';

  @override
  String get invalidTvIpv4 => 'Enter a valid TV IPv4 address.';

  @override
  String get pcSoundMute => 'Mute PC speakers';

  @override
  String get pcSoundMuteDescription =>
      'Mute the Windows audio capture endpoint only while mirroring. TV audio streaming continues.';

  @override
  String get pcSoundMuteOff => 'PC speaker mute is off.';

  @override
  String get pcSoundMuteWaiting => 'Waiting for audio capture to start.';

  @override
  String get pcSoundMuteRestoring => 'Restoring the Windows audio mute state.';

  @override
  String get pcSoundMuteActive =>
      'The Windows audio capture endpoint is muted.';

  @override
  String get pcSoundMuteAlreadyMuted =>
      'Windows was already muted before mirroring.';

  @override
  String get pcSoundMuteUserChanged =>
      'Mute changed in Windows. The app will leave it as set.';

  @override
  String get pcSoundMuteEndpointUnavailable =>
      'The audio capture endpoint is unavailable.';

  @override
  String get pcSoundMuteControlUnavailable =>
      'Windows does not expose mute control for this endpoint.';

  @override
  String get pcSoundMuteApplyFailed =>
      'Could not mute the Windows audio endpoint.';

  @override
  String get pcSoundMuteRestoreFailed =>
      'Could not restore the previous Windows mute state.';

  @override
  String get pcSoundMuteCaptureFailed =>
      'Audio capture stopped. PC speakers were not muted.';

  @override
  String get pcSoundMuteOnlyDuringMirroring =>
      'PC speaker mute applies only while mirroring.';

  @override
  String get fourKSelectDisplay => 'Select a 4K display to use this profile.';

  @override
  String get fourKDisplayTooSmall =>
      'The selected capture display is smaller than 3840 x 2160.';

  @override
  String get experimental => 'Experimental';

  @override
  String get profile720p30Hq => '720p30 HQ';

  @override
  String get profile1080p30Hq => '1080p30 HQ';

  @override
  String get profile1080p24Cinema => '1080p24 Cinema';

  @override
  String get profile1080p60 => 'FHD 1080p60';

  @override
  String get profile720p30Compat => '720p30 Compat';

  @override
  String get profile4k30 => '4K 30fps';

  @override
  String get profileDesc720p30Hq => 'Low-latency 720p30 H.264';

  @override
  String get profileDesc1080p30Hq => 'Balanced 1080p30 H.264';

  @override
  String get profileDesc1080p24Cinema =>
      'FHD 24fps Cinema H.264 with display pacing';

  @override
  String get profileDesc1080p60 =>
      'FHD 60fps Mirror H.264 at 14 Mbps (Experimental)';

  @override
  String get profileDesc720p30Compat => 'Lower bitrate 720p30 H.264';

  @override
  String get profileDesc4k30 =>
      'Requires compatible hardware encoder, Android TV decoder, and wired LAN';

  @override
  String get stateReady => 'Ready';

  @override
  String get stateStarting => 'Starting';

  @override
  String get stateListening => 'Waiting for TV';

  @override
  String get stateConnecting => 'Connecting';

  @override
  String get stateNegotiating => 'Preparing stream';

  @override
  String get stateWaitingForSurface => 'Waiting for TV display';

  @override
  String get stateWaitingForKeyFrame => 'Waiting for first frame';

  @override
  String get stateStreaming => 'Mirroring';

  @override
  String get statePaused => 'Paused';

  @override
  String get stateResuming => 'Resuming';

  @override
  String get stateStopping => 'Stopping';

  @override
  String get stateRestoring => 'Restoring';

  @override
  String get stateFailed => 'Failed';

  @override
  String get statusReady => 'Select a display and enter the TV address.';

  @override
  String get statusStarting => 'Preparing Windows screen and audio capture.';

  @override
  String get statusListening => 'Waiting for the TV to connect.';

  @override
  String get statusConnecting => 'Connecting to the TV.';

  @override
  String get statusNegotiating => 'Preparing the video stream.';

  @override
  String get statusWaitingForSurface =>
      'Waiting for the TV display to be ready.';

  @override
  String get statusWaitingForKeyFrame => 'Waiting for the first video frame.';

  @override
  String get statusStreaming => 'Sending video to the TV.';

  @override
  String get statusPaused => 'Playback is paused on the TV.';

  @override
  String get statusResuming => 'Resuming video playback.';

  @override
  String get statusStopping => 'Stopping the mirror session.';

  @override
  String get statusRestoring => 'Restoring session resources.';

  @override
  String get statusFailed =>
      'The session could not continue. Check diagnostics for details.';

  @override
  String get performance => 'Performance';

  @override
  String get capture => 'Capture';

  @override
  String get profile => 'Profile';

  @override
  String get fallback => 'Fallback';

  @override
  String get targetActual => 'Target / actual';

  @override
  String get callback => 'Callback';

  @override
  String get intervalP95 => 'Interval p95';

  @override
  String get targetInterval => 'Target interval';

  @override
  String get replacedCadence => 'Replaced / cadence';

  @override
  String get queueDepth => 'Queue depth';

  @override
  String get convertEncode => 'Convert / Encode';

  @override
  String get admissionAccepted => 'Admission / accepted';

  @override
  String get converted => 'Converted';

  @override
  String get encoderInput => 'Encoder input';

  @override
  String get encoded => 'Encoded';

  @override
  String get convertPath => 'Convert path';

  @override
  String get encodeAvgP95 => 'Encode avg/p95';

  @override
  String get encoder => 'Encoder';

  @override
  String get fourKCapability => '4K capability';

  @override
  String get backpressure => 'Backpressure';

  @override
  String get processInOutP95 => 'Process in/out p95';

  @override
  String get readbackReuse => 'Readback / reuse';

  @override
  String get network => 'Network';

  @override
  String get sent => 'Sent';

  @override
  String get sendIntervalP95 => 'Send interval p95';

  @override
  String get sendDuration => 'Send duration';

  @override
  String get socketCalls => 'Socket calls';

  @override
  String get pending => 'Pending';

  @override
  String get queueWaitAvgP95 => 'Queue wait avg/p95';

  @override
  String get staleVideoDrops => 'Stale video drops';

  @override
  String get audio => 'Audio';

  @override
  String get audioState => 'State';

  @override
  String get audioDevice => 'Device';

  @override
  String get inputEncoded => 'Input / encoded';

  @override
  String get captureSent => 'Capture / sent';

  @override
  String get encodeAverage => 'Encode avg';

  @override
  String get queueDropped => 'Queue / dropped';

  @override
  String get writerWaitVA => 'Writer wait V/A';

  @override
  String get audioError => 'Audio error';

  @override
  String get tvAudioPath => 'TV audio path';

  @override
  String get pcMuteRequested => 'PC mute requested';

  @override
  String get pcMuteApplied => 'PC mute applied';

  @override
  String get pcMuteActual => 'Windows mute state';

  @override
  String get pcMuteOriginal => 'Original mute state';

  @override
  String get pcMuteExternalChange => 'Changed in Windows';

  @override
  String get pcMuteTargetDevice => 'Mute target device ID';

  @override
  String get pcMuteErrorCode => 'Mute error code';

  @override
  String get playbackControl => 'Playback control';

  @override
  String get pauseResume => 'Pause / resume';

  @override
  String get ackError => 'ACK / error';

  @override
  String get resumeConfigResend => 'Resume config resend';

  @override
  String get capturedTotal => 'Captured total';

  @override
  String get lastSequence => 'Last sequence';

  @override
  String get intentionalSkip => 'Intentional skip';

  @override
  String get realDrops => 'Real drops';

  @override
  String get configSent => 'Config sent';

  @override
  String get keyFrames => 'Key frames';

  @override
  String get totalDropped => 'Total dropped';

  @override
  String get packets => 'Packets';

  @override
  String get bytes => 'Bytes';

  @override
  String get sendCompleted => 'Send completed';

  @override
  String get captureToEncode => 'Capture -> encode';

  @override
  String get valueDisabled => 'disabled';

  @override
  String get valueUnknown => 'unknown';

  @override
  String get valueHardware => 'hardware';

  @override
  String get valueSoftware => 'software';

  @override
  String get valueCapturing => 'capturing';

  @override
  String get valueStarting => 'starting';

  @override
  String get valueFailed => 'failed';

  @override
  String get valueReadback => 'readback';

  @override
  String get valueZeroCopy => 'zero-copy';

  @override
  String get valueReuse => 'reuse';

  @override
  String get valueAllocate => 'allocate';
}
