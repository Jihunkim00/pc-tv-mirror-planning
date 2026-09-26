import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemLanguage.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemLanguage;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get languageKorean;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get languageJapanese;

  /// No description provided for @monitorSource.
  ///
  /// In en, this message translates to:
  /// **'Monitor source'**
  String get monitorSource;

  /// No description provided for @noDisplays.
  ///
  /// In en, this message translates to:
  /// **'No displays found.'**
  String get noDisplays;

  /// No description provided for @betaVersion.
  ///
  /// In en, this message translates to:
  /// **'Beta version'**
  String get betaVersion;

  /// No description provided for @refreshDisplays.
  ///
  /// In en, this message translates to:
  /// **'Refresh displays'**
  String get refreshDisplays;

  /// No description provided for @copyDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get copyDiagnostics;

  /// No description provided for @receiverIp.
  ///
  /// In en, this message translates to:
  /// **'TV IP address'**
  String get receiverIp;

  /// No description provided for @receiverIpExample.
  ///
  /// In en, this message translates to:
  /// **'Example: 192.168.1.40'**
  String get receiverIpExample;

  /// No description provided for @controlPort.
  ///
  /// In en, this message translates to:
  /// **'Control port'**
  String get controlPort;

  /// No description provided for @videoProfile.
  ///
  /// In en, this message translates to:
  /// **'Video profile'**
  String get videoProfile;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @sessionLog.
  ///
  /// In en, this message translates to:
  /// **'Session log'**
  String get sessionLog;

  /// No description provided for @diagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied to clipboard.'**
  String get diagnosticsCopied;

  /// No description provided for @diagnosticsCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy diagnostics.'**
  String get diagnosticsCopyFailed;

  /// No description provided for @invalidTvIpv4.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid TV IPv4 address.'**
  String get invalidTvIpv4;

  /// No description provided for @pcSoundMute.
  ///
  /// In en, this message translates to:
  /// **'Mute PC speakers'**
  String get pcSoundMute;

  /// No description provided for @pcSoundMuteDescription.
  ///
  /// In en, this message translates to:
  /// **'Mute the Windows audio capture endpoint only while mirroring. TV audio streaming continues.'**
  String get pcSoundMuteDescription;

  /// No description provided for @pcSoundMuteOff.
  ///
  /// In en, this message translates to:
  /// **'PC speaker mute is off.'**
  String get pcSoundMuteOff;

  /// No description provided for @pcSoundMuteWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for audio capture to start.'**
  String get pcSoundMuteWaiting;

  /// No description provided for @pcSoundMuteRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring the Windows audio mute state.'**
  String get pcSoundMuteRestoring;

  /// No description provided for @pcSoundMuteActive.
  ///
  /// In en, this message translates to:
  /// **'The Windows audio capture endpoint is muted.'**
  String get pcSoundMuteActive;

  /// No description provided for @pcSoundMuteAlreadyMuted.
  ///
  /// In en, this message translates to:
  /// **'Windows was already muted before mirroring.'**
  String get pcSoundMuteAlreadyMuted;

  /// No description provided for @pcSoundMuteUserChanged.
  ///
  /// In en, this message translates to:
  /// **'Mute changed in Windows. The app will leave it as set.'**
  String get pcSoundMuteUserChanged;

  /// No description provided for @pcSoundMuteEndpointUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The audio capture endpoint is unavailable.'**
  String get pcSoundMuteEndpointUnavailable;

  /// No description provided for @pcSoundMuteControlUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Windows does not expose mute control for this endpoint.'**
  String get pcSoundMuteControlUnavailable;

  /// No description provided for @pcSoundMuteApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not mute the Windows audio endpoint.'**
  String get pcSoundMuteApplyFailed;

  /// No description provided for @pcSoundMuteRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore the previous Windows mute state.'**
  String get pcSoundMuteRestoreFailed;

  /// No description provided for @pcSoundMuteCaptureFailed.
  ///
  /// In en, this message translates to:
  /// **'Audio capture stopped. PC speakers were not muted.'**
  String get pcSoundMuteCaptureFailed;

  /// No description provided for @pcSoundMuteOnlyDuringMirroring.
  ///
  /// In en, this message translates to:
  /// **'PC speaker mute applies only while mirroring.'**
  String get pcSoundMuteOnlyDuringMirroring;

  /// No description provided for @fourKSelectDisplay.
  ///
  /// In en, this message translates to:
  /// **'Select a 4K display to use this profile.'**
  String get fourKSelectDisplay;

  /// No description provided for @fourKDisplayTooSmall.
  ///
  /// In en, this message translates to:
  /// **'The selected capture display is smaller than 3840 x 2160.'**
  String get fourKDisplayTooSmall;

  /// No description provided for @experimental.
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get experimental;

  /// No description provided for @profile720p30Hq.
  ///
  /// In en, this message translates to:
  /// **'720p30 HQ'**
  String get profile720p30Hq;

  /// No description provided for @profile1080p30Hq.
  ///
  /// In en, this message translates to:
  /// **'1080p30 HQ'**
  String get profile1080p30Hq;

  /// No description provided for @profile1080p24Cinema.
  ///
  /// In en, this message translates to:
  /// **'1080p24 Cinema'**
  String get profile1080p24Cinema;

  /// No description provided for @profile1080p60.
  ///
  /// In en, this message translates to:
  /// **'FHD 1080p60'**
  String get profile1080p60;

  /// No description provided for @profile720p30Compat.
  ///
  /// In en, this message translates to:
  /// **'720p30 Compat'**
  String get profile720p30Compat;

  /// No description provided for @profile4k30.
  ///
  /// In en, this message translates to:
  /// **'4K 30fps'**
  String get profile4k30;

  /// No description provided for @profileDesc720p30Hq.
  ///
  /// In en, this message translates to:
  /// **'Low-latency 720p30 H.264'**
  String get profileDesc720p30Hq;

  /// No description provided for @profileDesc1080p30Hq.
  ///
  /// In en, this message translates to:
  /// **'Balanced 1080p30 H.264'**
  String get profileDesc1080p30Hq;

  /// No description provided for @profileDesc1080p24Cinema.
  ///
  /// In en, this message translates to:
  /// **'FHD 24fps Cinema H.264 with display pacing'**
  String get profileDesc1080p24Cinema;

  /// No description provided for @profileDesc1080p60.
  ///
  /// In en, this message translates to:
  /// **'FHD 60fps Mirror H.264 at 14 Mbps (Experimental)'**
  String get profileDesc1080p60;

  /// No description provided for @profileDesc720p30Compat.
  ///
  /// In en, this message translates to:
  /// **'Lower bitrate 720p30 H.264'**
  String get profileDesc720p30Compat;

  /// No description provided for @profileDesc4k30.
  ///
  /// In en, this message translates to:
  /// **'Requires compatible hardware encoder, Android TV decoder, and wired LAN'**
  String get profileDesc4k30;

  /// No description provided for @stateReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get stateReady;

  /// No description provided for @stateStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get stateStarting;

  /// No description provided for @stateListening.
  ///
  /// In en, this message translates to:
  /// **'Waiting for TV'**
  String get stateListening;

  /// No description provided for @stateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get stateConnecting;

  /// No description provided for @stateNegotiating.
  ///
  /// In en, this message translates to:
  /// **'Preparing stream'**
  String get stateNegotiating;

  /// No description provided for @stateWaitingForSurface.
  ///
  /// In en, this message translates to:
  /// **'Waiting for TV display'**
  String get stateWaitingForSurface;

  /// No description provided for @stateWaitingForKeyFrame.
  ///
  /// In en, this message translates to:
  /// **'Waiting for first frame'**
  String get stateWaitingForKeyFrame;

  /// No description provided for @stateStreaming.
  ///
  /// In en, this message translates to:
  /// **'Mirroring'**
  String get stateStreaming;

  /// No description provided for @statePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statePaused;

  /// No description provided for @stateResuming.
  ///
  /// In en, this message translates to:
  /// **'Resuming'**
  String get stateResuming;

  /// No description provided for @stateStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get stateStopping;

  /// No description provided for @stateRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring'**
  String get stateRestoring;

  /// No description provided for @stateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get stateFailed;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Select a display and enter the TV address.'**
  String get statusReady;

  /// No description provided for @statusStarting.
  ///
  /// In en, this message translates to:
  /// **'Preparing Windows screen and audio capture.'**
  String get statusStarting;

  /// No description provided for @statusListening.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the TV to connect.'**
  String get statusListening;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the TV.'**
  String get statusConnecting;

  /// No description provided for @statusNegotiating.
  ///
  /// In en, this message translates to:
  /// **'Preparing the video stream.'**
  String get statusNegotiating;

  /// No description provided for @statusWaitingForSurface.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the TV display to be ready.'**
  String get statusWaitingForSurface;

  /// No description provided for @statusWaitingForKeyFrame.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the first video frame.'**
  String get statusWaitingForKeyFrame;

  /// No description provided for @statusStreaming.
  ///
  /// In en, this message translates to:
  /// **'Sending video to the TV.'**
  String get statusStreaming;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Playback is paused on the TV.'**
  String get statusPaused;

  /// No description provided for @statusResuming.
  ///
  /// In en, this message translates to:
  /// **'Resuming video playback.'**
  String get statusResuming;

  /// No description provided for @statusStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping the mirror session.'**
  String get statusStopping;

  /// No description provided for @statusRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring session resources.'**
  String get statusRestoring;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'The session could not continue. Check diagnostics for details.'**
  String get statusFailed;

  /// No description provided for @performance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performance;

  /// No description provided for @capture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get capture;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @fallback.
  ///
  /// In en, this message translates to:
  /// **'Fallback'**
  String get fallback;

  /// No description provided for @targetActual.
  ///
  /// In en, this message translates to:
  /// **'Target / actual'**
  String get targetActual;

  /// No description provided for @callback.
  ///
  /// In en, this message translates to:
  /// **'Callback'**
  String get callback;

  /// No description provided for @intervalP95.
  ///
  /// In en, this message translates to:
  /// **'Interval p95'**
  String get intervalP95;

  /// No description provided for @targetInterval.
  ///
  /// In en, this message translates to:
  /// **'Target interval'**
  String get targetInterval;

  /// No description provided for @replacedCadence.
  ///
  /// In en, this message translates to:
  /// **'Replaced / cadence'**
  String get replacedCadence;

  /// No description provided for @queueDepth.
  ///
  /// In en, this message translates to:
  /// **'Queue depth'**
  String get queueDepth;

  /// No description provided for @convertEncode.
  ///
  /// In en, this message translates to:
  /// **'Convert / Encode'**
  String get convertEncode;

  /// No description provided for @admissionAccepted.
  ///
  /// In en, this message translates to:
  /// **'Admission / accepted'**
  String get admissionAccepted;

  /// No description provided for @converted.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get converted;

  /// No description provided for @encoderInput.
  ///
  /// In en, this message translates to:
  /// **'Encoder input'**
  String get encoderInput;

  /// No description provided for @encoded.
  ///
  /// In en, this message translates to:
  /// **'Encoded'**
  String get encoded;

  /// No description provided for @convertPath.
  ///
  /// In en, this message translates to:
  /// **'Convert path'**
  String get convertPath;

  /// No description provided for @encodeAvgP95.
  ///
  /// In en, this message translates to:
  /// **'Encode avg/p95'**
  String get encodeAvgP95;

  /// No description provided for @encoder.
  ///
  /// In en, this message translates to:
  /// **'Encoder'**
  String get encoder;

  /// No description provided for @fourKCapability.
  ///
  /// In en, this message translates to:
  /// **'4K capability'**
  String get fourKCapability;

  /// No description provided for @backpressure.
  ///
  /// In en, this message translates to:
  /// **'Backpressure'**
  String get backpressure;

  /// No description provided for @processInOutP95.
  ///
  /// In en, this message translates to:
  /// **'Process in/out p95'**
  String get processInOutP95;

  /// No description provided for @readbackReuse.
  ///
  /// In en, this message translates to:
  /// **'Readback / reuse'**
  String get readbackReuse;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @sendIntervalP95.
  ///
  /// In en, this message translates to:
  /// **'Send interval p95'**
  String get sendIntervalP95;

  /// No description provided for @sendDuration.
  ///
  /// In en, this message translates to:
  /// **'Send duration'**
  String get sendDuration;

  /// No description provided for @socketCalls.
  ///
  /// In en, this message translates to:
  /// **'Socket calls'**
  String get socketCalls;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @queueWaitAvgP95.
  ///
  /// In en, this message translates to:
  /// **'Queue wait avg/p95'**
  String get queueWaitAvgP95;

  /// No description provided for @staleVideoDrops.
  ///
  /// In en, this message translates to:
  /// **'Stale video drops'**
  String get staleVideoDrops;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @audioState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get audioState;

  /// No description provided for @audioDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get audioDevice;

  /// No description provided for @inputEncoded.
  ///
  /// In en, this message translates to:
  /// **'Input / encoded'**
  String get inputEncoded;

  /// No description provided for @captureSent.
  ///
  /// In en, this message translates to:
  /// **'Capture / sent'**
  String get captureSent;

  /// No description provided for @encodeAverage.
  ///
  /// In en, this message translates to:
  /// **'Encode avg'**
  String get encodeAverage;

  /// No description provided for @queueDropped.
  ///
  /// In en, this message translates to:
  /// **'Queue / dropped'**
  String get queueDropped;

  /// No description provided for @writerWaitVA.
  ///
  /// In en, this message translates to:
  /// **'Writer wait V/A'**
  String get writerWaitVA;

  /// No description provided for @audioError.
  ///
  /// In en, this message translates to:
  /// **'Audio error'**
  String get audioError;

  /// No description provided for @tvAudioPath.
  ///
  /// In en, this message translates to:
  /// **'TV audio path'**
  String get tvAudioPath;

  /// No description provided for @pcMuteRequested.
  ///
  /// In en, this message translates to:
  /// **'PC mute requested'**
  String get pcMuteRequested;

  /// No description provided for @pcMuteApplied.
  ///
  /// In en, this message translates to:
  /// **'PC mute applied'**
  String get pcMuteApplied;

  /// No description provided for @pcMuteActual.
  ///
  /// In en, this message translates to:
  /// **'Windows mute state'**
  String get pcMuteActual;

  /// No description provided for @pcMuteOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original mute state'**
  String get pcMuteOriginal;

  /// No description provided for @pcMuteExternalChange.
  ///
  /// In en, this message translates to:
  /// **'Changed in Windows'**
  String get pcMuteExternalChange;

  /// No description provided for @pcMuteTargetDevice.
  ///
  /// In en, this message translates to:
  /// **'Mute target device ID'**
  String get pcMuteTargetDevice;

  /// No description provided for @pcMuteErrorCode.
  ///
  /// In en, this message translates to:
  /// **'Mute error code'**
  String get pcMuteErrorCode;

  /// No description provided for @playbackControl.
  ///
  /// In en, this message translates to:
  /// **'Playback control'**
  String get playbackControl;

  /// No description provided for @pauseResume.
  ///
  /// In en, this message translates to:
  /// **'Pause / resume'**
  String get pauseResume;

  /// No description provided for @ackError.
  ///
  /// In en, this message translates to:
  /// **'ACK / error'**
  String get ackError;

  /// No description provided for @resumeConfigResend.
  ///
  /// In en, this message translates to:
  /// **'Resume config resend'**
  String get resumeConfigResend;

  /// No description provided for @capturedTotal.
  ///
  /// In en, this message translates to:
  /// **'Captured total'**
  String get capturedTotal;

  /// No description provided for @lastSequence.
  ///
  /// In en, this message translates to:
  /// **'Last sequence'**
  String get lastSequence;

  /// No description provided for @intentionalSkip.
  ///
  /// In en, this message translates to:
  /// **'Intentional skip'**
  String get intentionalSkip;

  /// No description provided for @realDrops.
  ///
  /// In en, this message translates to:
  /// **'Real drops'**
  String get realDrops;

  /// No description provided for @configSent.
  ///
  /// In en, this message translates to:
  /// **'Config sent'**
  String get configSent;

  /// No description provided for @keyFrames.
  ///
  /// In en, this message translates to:
  /// **'Key frames'**
  String get keyFrames;

  /// No description provided for @totalDropped.
  ///
  /// In en, this message translates to:
  /// **'Total dropped'**
  String get totalDropped;

  /// No description provided for @packets.
  ///
  /// In en, this message translates to:
  /// **'Packets'**
  String get packets;

  /// No description provided for @bytes.
  ///
  /// In en, this message translates to:
  /// **'Bytes'**
  String get bytes;

  /// No description provided for @sendCompleted.
  ///
  /// In en, this message translates to:
  /// **'Send completed'**
  String get sendCompleted;

  /// No description provided for @captureToEncode.
  ///
  /// In en, this message translates to:
  /// **'Capture -> encode'**
  String get captureToEncode;

  /// No description provided for @valueDisabled.
  ///
  /// In en, this message translates to:
  /// **'disabled'**
  String get valueDisabled;

  /// No description provided for @valueUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get valueUnknown;

  /// No description provided for @valueHardware.
  ///
  /// In en, this message translates to:
  /// **'hardware'**
  String get valueHardware;

  /// No description provided for @valueSoftware.
  ///
  /// In en, this message translates to:
  /// **'software'**
  String get valueSoftware;

  /// No description provided for @valueCapturing.
  ///
  /// In en, this message translates to:
  /// **'capturing'**
  String get valueCapturing;

  /// No description provided for @valueStarting.
  ///
  /// In en, this message translates to:
  /// **'starting'**
  String get valueStarting;

  /// No description provided for @valueFailed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get valueFailed;

  /// No description provided for @valueReadback.
  ///
  /// In en, this message translates to:
  /// **'readback'**
  String get valueReadback;

  /// No description provided for @valueZeroCopy.
  ///
  /// In en, this message translates to:
  /// **'zero-copy'**
  String get valueZeroCopy;

  /// No description provided for @valueReuse.
  ///
  /// In en, this message translates to:
  /// **'reuse'**
  String get valueReuse;

  /// No description provided for @valueAllocate.
  ///
  /// In en, this message translates to:
  /// **'allocate'**
  String get valueAllocate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
