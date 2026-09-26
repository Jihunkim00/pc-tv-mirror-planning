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

  /// No description provided for @waitingForVideoFrames.
  ///
  /// In en, this message translates to:
  /// **'Waiting for PC video frames'**
  String get waitingForVideoFrames;

  /// No description provided for @restartReceiver.
  ///
  /// In en, this message translates to:
  /// **'Restart receiver'**
  String get restartReceiver;

  /// No description provided for @fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get fullscreen;

  /// No description provided for @stopReceiver.
  ///
  /// In en, this message translates to:
  /// **'Stop receiver'**
  String get stopReceiver;

  /// No description provided for @autoFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Auto fullscreen'**
  String get autoFullscreen;

  /// No description provided for @fpsDebugOverlay.
  ///
  /// In en, this message translates to:
  /// **'FPS debug overlay'**
  String get fpsDebugOverlay;

  /// No description provided for @actualCodecTiming.
  ///
  /// In en, this message translates to:
  /// **'Actual codec render/display timing'**
  String get actualCodecTiming;

  /// No description provided for @fit.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get fit;

  /// No description provided for @fill.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get fill;

  /// No description provided for @controlPort.
  ///
  /// In en, this message translates to:
  /// **'Control port'**
  String get controlPort;

  /// No description provided for @tvAddress.
  ///
  /// In en, this message translates to:
  /// **'TV address'**
  String get tvAddress;

  /// No description provided for @protocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get protocol;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @fourK.
  ///
  /// In en, this message translates to:
  /// **'4K'**
  String get fourK;

  /// No description provided for @decoder.
  ///
  /// In en, this message translates to:
  /// **'Decoder'**
  String get decoder;

  /// No description provided for @surface.
  ///
  /// In en, this message translates to:
  /// **'Surface'**
  String get surface;

  /// No description provided for @performance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performance;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @receiveDecodePresent.
  ///
  /// In en, this message translates to:
  /// **'Receive / Decode / Present'**
  String get receiveDecodePresent;

  /// No description provided for @presentP95.
  ///
  /// In en, this message translates to:
  /// **'Present p95'**
  String get presentP95;

  /// No description provided for @latencyAvgP95.
  ///
  /// In en, this message translates to:
  /// **'Latency avg/p95'**
  String get latencyAvgP95;

  /// No description provided for @renderer.
  ///
  /// In en, this message translates to:
  /// **'Renderer'**
  String get renderer;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @drops.
  ///
  /// In en, this message translates to:
  /// **'Drops'**
  String get drops;

  /// No description provided for @sequenceGaps.
  ///
  /// In en, this message translates to:
  /// **'Sequence gaps'**
  String get sequenceGaps;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @audioCodec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get audioCodec;

  /// No description provided for @audioDecoder.
  ///
  /// In en, this message translates to:
  /// **'Decoder'**
  String get audioDecoder;

  /// No description provided for @track.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get track;

  /// No description provided for @audioSession.
  ///
  /// In en, this message translates to:
  /// **'Audio session'**
  String get audioSession;

  /// No description provided for @queuePcm.
  ///
  /// In en, this message translates to:
  /// **'Queue / PCM'**
  String get queuePcm;

  /// No description provided for @buffered.
  ///
  /// In en, this message translates to:
  /// **'Buffered'**
  String get buffered;

  /// No description provided for @avSync.
  ///
  /// In en, this message translates to:
  /// **'A/V sync'**
  String get avSync;

  /// No description provided for @avAvgP95.
  ///
  /// In en, this message translates to:
  /// **'A/V avg/p95'**
  String get avAvgP95;

  /// No description provided for @audioPackets.
  ///
  /// In en, this message translates to:
  /// **'Audio packets'**
  String get audioPackets;

  /// No description provided for @audioWrites.
  ///
  /// In en, this message translates to:
  /// **'Audio writes'**
  String get audioWrites;

  /// No description provided for @audioRecovery.
  ///
  /// In en, this message translates to:
  /// **'Audio recovery'**
  String get audioRecovery;

  /// No description provided for @audioReset.
  ///
  /// In en, this message translates to:
  /// **'Audio reset'**
  String get audioReset;

  /// No description provided for @audioExpected.
  ///
  /// In en, this message translates to:
  /// **'Audio expected'**
  String get audioExpected;

  /// No description provided for @audioDrops.
  ///
  /// In en, this message translates to:
  /// **'Audio drops'**
  String get audioDrops;

  /// No description provided for @audioResetReason.
  ///
  /// In en, this message translates to:
  /// **'Audio reset reason'**
  String get audioResetReason;

  /// No description provided for @audioError.
  ///
  /// In en, this message translates to:
  /// **'Audio error'**
  String get audioError;

  /// No description provided for @presentation.
  ///
  /// In en, this message translates to:
  /// **'Presentation'**
  String get presentation;

  /// No description provided for @autoEntered.
  ///
  /// In en, this message translates to:
  /// **'Auto entered'**
  String get autoEntered;

  /// No description provided for @userExited.
  ///
  /// In en, this message translates to:
  /// **'User exited'**
  String get userExited;

  /// No description provided for @playback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playback;

  /// No description provided for @scaleMode.
  ///
  /// In en, this message translates to:
  /// **'Scale mode'**
  String get scaleMode;

  /// No description provided for @display.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// No description provided for @videoView.
  ///
  /// In en, this message translates to:
  /// **'Video view'**
  String get videoView;

  /// No description provided for @aspectError.
  ///
  /// In en, this message translates to:
  /// **'Aspect error'**
  String get aspectError;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @bytes.
  ///
  /// In en, this message translates to:
  /// **'Bytes'**
  String get bytes;

  /// No description provided for @config.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get config;

  /// No description provided for @accessUnits.
  ///
  /// In en, this message translates to:
  /// **'Access units'**
  String get accessUnits;

  /// No description provided for @keyFrames.
  ///
  /// In en, this message translates to:
  /// **'Key frames'**
  String get keyFrames;

  /// No description provided for @decoderIo.
  ///
  /// In en, this message translates to:
  /// **'Decoder input/output'**
  String get decoderIo;

  /// No description provided for @releasedToSurface.
  ///
  /// In en, this message translates to:
  /// **'Released to surface'**
  String get releasedToSurface;

  /// No description provided for @codecCreateRelease.
  ///
  /// In en, this message translates to:
  /// **'Codec create/release'**
  String get codecCreateRelease;

  /// No description provided for @surfaceLifecycle.
  ///
  /// In en, this message translates to:
  /// **'Surface lifecycle'**
  String get surfaceLifecycle;

  /// No description provided for @surfaceValid.
  ///
  /// In en, this message translates to:
  /// **'Surface valid'**
  String get surfaceValid;

  /// No description provided for @surfaceSize.
  ///
  /// In en, this message translates to:
  /// **'Surface size'**
  String get surfaceSize;

  /// No description provided for @surfaceZOrder.
  ///
  /// In en, this message translates to:
  /// **'Surface z-order'**
  String get surfaceZOrder;

  /// No description provided for @configuredOutput.
  ///
  /// In en, this message translates to:
  /// **'Configured/output'**
  String get configuredOutput;

  /// No description provided for @outputCrop.
  ///
  /// In en, this message translates to:
  /// **'Output crop'**
  String get outputCrop;

  /// No description provided for @lastError.
  ///
  /// In en, this message translates to:
  /// **'Last error'**
  String get lastError;

  /// No description provided for @receiverLog.
  ///
  /// In en, this message translates to:
  /// **'Receiver log'**
  String get receiverLog;

  /// No description provided for @state.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get state;

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'idle'**
  String get idle;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get checking;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @mediaCodecReady.
  ///
  /// In en, this message translates to:
  /// **'MediaCodec ready'**
  String get mediaCodecReady;

  /// No description provided for @surfaceViewReady.
  ///
  /// In en, this message translates to:
  /// **'SurfaceView ready'**
  String get surfaceViewReady;

  /// No description provided for @receiverStarting.
  ///
  /// In en, this message translates to:
  /// **'Receiver is starting.'**
  String get receiverStarting;

  /// No description provided for @receiverStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Receiver could not start.'**
  String get receiverStartFailed;

  /// No description provided for @receiverStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Receiver stop failed.'**
  String get receiverStopFailed;

  /// No description provided for @videoDebug.
  ///
  /// In en, this message translates to:
  /// **'VIDEO DEBUG'**
  String get videoDebug;

  /// No description provided for @renderMode.
  ///
  /// In en, this message translates to:
  /// **'Render mode'**
  String get renderMode;

  /// No description provided for @releaseImmediateScheduled.
  ///
  /// In en, this message translates to:
  /// **'Release immediate/scheduled'**
  String get releaseImmediateScheduled;

  /// No description provided for @input.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get input;

  /// No description provided for @codecRendered.
  ///
  /// In en, this message translates to:
  /// **'Codec rendered'**
  String get codecRendered;

  /// No description provided for @renderP50P95Max.
  ///
  /// In en, this message translates to:
  /// **'Render p50/p95/max'**
  String get renderP50P95Max;

  /// No description provided for @jitterP95.
  ///
  /// In en, this message translates to:
  /// **'Jitter p95'**
  String get jitterP95;

  /// No description provided for @gaps.
  ///
  /// In en, this message translates to:
  /// **'Gaps'**
  String get gaps;

  /// No description provided for @pts.
  ///
  /// In en, this message translates to:
  /// **'PTS'**
  String get pts;

  /// No description provided for @drift.
  ///
  /// In en, this message translates to:
  /// **'drift'**
  String get drift;

  /// No description provided for @mode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mode;

  /// No description provided for @receiverStateReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get receiverStateReady;

  /// No description provided for @receiverStateStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get receiverStateStarting;

  /// No description provided for @receiverStateListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get receiverStateListening;

  /// No description provided for @receiverStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get receiverStateConnecting;

  /// No description provided for @receiverStateNegotiating.
  ///
  /// In en, this message translates to:
  /// **'Negotiating'**
  String get receiverStateNegotiating;

  /// No description provided for @receiverStateWaitingForSurface.
  ///
  /// In en, this message translates to:
  /// **'Waiting for display'**
  String get receiverStateWaitingForSurface;

  /// No description provided for @receiverStateWaitingForKeyFrame.
  ///
  /// In en, this message translates to:
  /// **'Waiting for first frame'**
  String get receiverStateWaitingForKeyFrame;

  /// No description provided for @receiverStateStreaming.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get receiverStateStreaming;

  /// No description provided for @receiverStatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get receiverStatePaused;

  /// No description provided for @receiverStateResuming.
  ///
  /// In en, this message translates to:
  /// **'Resuming'**
  String get receiverStateResuming;

  /// No description provided for @receiverStateDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get receiverStateDisconnected;

  /// No description provided for @receiverStateError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get receiverStateError;

  /// No description provided for @receiverStateStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get receiverStateStopping;

  /// No description provided for @receiverStateRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring'**
  String get receiverStateRestoring;

  /// No description provided for @receiverStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get receiverStateFailed;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Receiver is ready for a PC.'**
  String get statusReady;

  /// No description provided for @statusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting the receiver.'**
  String get statusStarting;

  /// No description provided for @statusListening.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a PC connection.'**
  String get statusListening;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'PC connected; preparing the session.'**
  String get statusConnecting;

  /// No description provided for @statusNegotiating.
  ///
  /// In en, this message translates to:
  /// **'Negotiating the video stream.'**
  String get statusNegotiating;

  /// No description provided for @statusWaitingForSurface.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the TV display surface.'**
  String get statusWaitingForSurface;

  /// No description provided for @statusWaitingForKeyFrame.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the first video frame.'**
  String get statusWaitingForKeyFrame;

  /// No description provided for @statusStreaming.
  ///
  /// In en, this message translates to:
  /// **'Receiving video from the PC.'**
  String get statusStreaming;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Playback is paused.'**
  String get statusPaused;

  /// No description provided for @statusResuming.
  ///
  /// In en, this message translates to:
  /// **'Resuming playback.'**
  String get statusResuming;

  /// No description provided for @statusStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping the receiver session.'**
  String get statusStopping;

  /// No description provided for @statusRestoring.
  ///
  /// In en, this message translates to:
  /// **'Releasing receiver resources.'**
  String get statusRestoring;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Receiver error. Check the receiver log for details.'**
  String get statusFailed;
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
