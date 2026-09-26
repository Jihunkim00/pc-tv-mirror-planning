// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get language => '言語';

  @override
  String get systemLanguage => 'システム標準';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageJapanese => '日本語';

  @override
  String get monitorSource => 'モニターソース';

  @override
  String get noDisplays => 'ディスプレイが見つかりません。';

  @override
  String get betaVersion => 'ベータ版';

  @override
  String get refreshDisplays => 'ディスプレイを更新';

  @override
  String get copyDiagnostics => '診断情報をコピー';

  @override
  String get receiverIp => 'テレビの IP アドレス';

  @override
  String get receiverIpExample => '例: 192.168.1.40';

  @override
  String get controlPort => '制御ポート';

  @override
  String get videoProfile => '映像プロファイル';

  @override
  String get start => '開始';

  @override
  String get stop => '停止';

  @override
  String get sessionLog => 'セッションログ';

  @override
  String get diagnosticsCopied => '診断情報をクリップボードにコピーしました。';

  @override
  String get diagnosticsCopyFailed => '診断情報をコピーできませんでした。';

  @override
  String get invalidTvIpv4 => '有効なテレビの IPv4 アドレスを入力してください。';

  @override
  String get pcSoundMute => 'PC スピーカーをミュート';

  @override
  String get pcSoundMuteDescription =>
      'ミラーリング中のみ Windows の音声キャプチャエンドポイントをミュートします。テレビへの音声配信は続きます。';

  @override
  String get pcSoundMuteOff => 'PC スピーカーのミュートはオフです。';

  @override
  String get pcSoundMuteWaiting => '音声キャプチャの開始を待っています。';

  @override
  String get pcSoundMuteRestoring => 'Windows のミュート状態を復元しています。';

  @override
  String get pcSoundMuteActive => 'Windows の音声キャプチャエンドポイントをミュートしています。';

  @override
  String get pcSoundMuteAlreadyMuted => 'ミラーリング開始前から Windows はミュートされていました。';

  @override
  String get pcSoundMuteUserChanged => 'Windows 側でミュート状態が変更されたため、その状態を維持します。';

  @override
  String get pcSoundMuteEndpointUnavailable => '音声キャプチャエンドポイントを利用できません。';

  @override
  String get pcSoundMuteControlUnavailable =>
      'このエンドポイントでは Windows のミュート制御を利用できません。';

  @override
  String get pcSoundMuteApplyFailed => 'Windows の音声エンドポイントをミュートできませんでした。';

  @override
  String get pcSoundMuteRestoreFailed => '以前の Windows のミュート状態を復元できませんでした。';

  @override
  String get pcSoundMuteCaptureFailed => '音声キャプチャが停止したため、PC スピーカーはミュートされていません。';

  @override
  String get pcSoundMuteOnlyDuringMirroring => 'PC スピーカーのミュートはミラーリング中のみ適用されます。';

  @override
  String get fourKSelectDisplay => 'このプロファイルを使うには 4K ディスプレイを選択してください。';

  @override
  String get fourKDisplayTooSmall => '選択したキャプチャディスプレイは 3840 x 2160 未満です。';

  @override
  String get experimental => '実験的';

  @override
  String get profile720p30Hq => '720p30 高画質';

  @override
  String get profile1080p30Hq => '1080p30 高画質';

  @override
  String get profile1080p24Cinema => '1080p24 シネマ';

  @override
  String get profile1080p60 => 'FHD 1080p60';

  @override
  String get profile720p30Compat => '720p30 互換';

  @override
  String get profile4k30 => '4K 30fps';

  @override
  String get profileDesc720p30Hq => '低遅延 720p30 H.264';

  @override
  String get profileDesc1080p30Hq => 'バランス重視 1080p30 H.264';

  @override
  String get profileDesc1080p24Cinema => 'ディスプレイ周期に合わせた FHD 24fps シネマ H.264';

  @override
  String get profileDesc1080p60 => '14 Mbps FHD 60fps ミラーリング H.264（実験的）';

  @override
  String get profileDesc720p30Compat => '低ビットレート 720p30 H.264';

  @override
  String get profileDesc4k30 =>
      '対応するハードウェアエンコーダー、Android TV デコーダー、有線 LAN が必要です';

  @override
  String get stateReady => '準備完了';

  @override
  String get stateStarting => '起動中';

  @override
  String get stateListening => 'テレビ接続待ち';

  @override
  String get stateConnecting => '接続中';

  @override
  String get stateNegotiating => 'ストリームを準備中';

  @override
  String get stateWaitingForSurface => 'テレビ画面待ち';

  @override
  String get stateWaitingForKeyFrame => '最初のフレーム待ち';

  @override
  String get stateStreaming => 'ミラーリング中';

  @override
  String get statePaused => '一時停止中';

  @override
  String get stateResuming => '再開中';

  @override
  String get stateStopping => '停止中';

  @override
  String get stateRestoring => '復元中';

  @override
  String get stateFailed => '失敗';

  @override
  String get statusReady => 'ディスプレイを選択してテレビのアドレスを入力してください。';

  @override
  String get statusStarting => 'Windows の画面と音声キャプチャを準備しています。';

  @override
  String get statusListening => 'テレビからの接続を待っています。';

  @override
  String get statusConnecting => 'テレビに接続しています。';

  @override
  String get statusNegotiating => '映像ストリームを準備しています。';

  @override
  String get statusWaitingForSurface => 'テレビ画面の準備を待っています。';

  @override
  String get statusWaitingForKeyFrame => '最初の映像フレームを待っています。';

  @override
  String get statusStreaming => 'テレビに映像を送信しています。';

  @override
  String get statusPaused => 'テレビで再生を一時停止しています。';

  @override
  String get statusResuming => '映像の再生を再開しています。';

  @override
  String get statusStopping => 'ミラーリングセッションを停止しています。';

  @override
  String get statusRestoring => 'セッション リソースを復元しています。';

  @override
  String get statusFailed => 'セッションを続行できません。詳細は診断情報を確認してください。';

  @override
  String get performance => 'パフォーマンス';

  @override
  String get capture => 'キャプチャ';

  @override
  String get profile => 'プロファイル';

  @override
  String get fallback => 'フォールバック';

  @override
  String get targetActual => '目標 / 実測';

  @override
  String get callback => 'コールバック';

  @override
  String get intervalP95 => '間隔 p95';

  @override
  String get targetInterval => '目標間隔';

  @override
  String get replacedCadence => '置換 / 周期';

  @override
  String get queueDepth => 'キュー深度';

  @override
  String get convertEncode => '変換 / エンコード';

  @override
  String get admissionAccepted => '受付 / 承認';

  @override
  String get converted => '変換済み';

  @override
  String get encoderInput => 'エンコーダー入力';

  @override
  String get encoded => 'エンコード済み';

  @override
  String get convertPath => '変換経路';

  @override
  String get encodeAvgP95 => 'エンコード平均/p95';

  @override
  String get encoder => 'エンコーダー';

  @override
  String get fourKCapability => '4K 対応';

  @override
  String get backpressure => 'バックプレッシャー';

  @override
  String get processInOutP95 => '処理 入力/出力 p95';

  @override
  String get readbackReuse => '読み戻し / 再利用';

  @override
  String get network => 'ネットワーク';

  @override
  String get sent => '送信済み';

  @override
  String get sendIntervalP95 => '送信間隔 p95';

  @override
  String get sendDuration => '送信時間';

  @override
  String get socketCalls => 'ソケット呼び出し';

  @override
  String get pending => '保留中';

  @override
  String get queueWaitAvgP95 => 'キュー待ち平均/p95';

  @override
  String get staleVideoDrops => '古い映像の破棄';

  @override
  String get audio => '音声';

  @override
  String get audioState => '状態';

  @override
  String get audioDevice => 'デバイス';

  @override
  String get inputEncoded => '入力 / エンコード';

  @override
  String get captureSent => 'キャプチャ / 送信';

  @override
  String get encodeAverage => 'エンコード平均';

  @override
  String get queueDropped => 'キュー / 破棄';

  @override
  String get writerWaitVA => '書き込み待ち 映像/音声';

  @override
  String get audioError => '音声エラー';

  @override
  String get tvAudioPath => 'テレビ音声経路';

  @override
  String get pcMuteRequested => 'PC ミュート要求';

  @override
  String get pcMuteApplied => 'PC ミュート適用';

  @override
  String get pcMuteActual => 'Windows ミュート状態';

  @override
  String get pcMuteOriginal => '開始前のミュート状態';

  @override
  String get pcMuteExternalChange => 'Windows 側で変更';

  @override
  String get pcMuteTargetDevice => 'ミュート対象デバイス ID';

  @override
  String get pcMuteErrorCode => 'ミュートエラーコード';

  @override
  String get playbackControl => '再生制御';

  @override
  String get pauseResume => '一時停止 / 再開';

  @override
  String get ackError => 'ACK / エラー';

  @override
  String get resumeConfigResend => '再開設定の再送';

  @override
  String get capturedTotal => 'キャプチャ合計';

  @override
  String get lastSequence => '最後のシーケンス';

  @override
  String get intentionalSkip => '意図的なスキップ';

  @override
  String get realDrops => '実際の破棄';

  @override
  String get configSent => '設定送信';

  @override
  String get keyFrames => 'キーフレーム';

  @override
  String get totalDropped => '合計破棄';

  @override
  String get packets => 'パケット';

  @override
  String get bytes => 'バイト';

  @override
  String get sendCompleted => '送信完了';

  @override
  String get captureToEncode => 'キャプチャ -> エンコード';

  @override
  String get valueDisabled => '無効';

  @override
  String get valueUnknown => '不明';

  @override
  String get valueHardware => 'ハードウェア';

  @override
  String get valueSoftware => 'ソフトウェア';

  @override
  String get valueCapturing => 'キャプチャ中';

  @override
  String get valueStarting => '起動中';

  @override
  String get valueFailed => '失敗';

  @override
  String get valueReadback => '読み戻し';

  @override
  String get valueZeroCopy => 'ゼロコピー';

  @override
  String get valueReuse => '再利用';

  @override
  String get valueAllocate => '割り当て';
}
