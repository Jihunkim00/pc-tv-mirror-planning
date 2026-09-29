// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get waitingForVideoFrames => 'PC 映像フレーム待ち';

  @override
  String get restartReceiver => 'レシーバーを再起動';

  @override
  String get fullscreen => '全画面表示';

  @override
  String get stopReceiver => 'レシーバーを停止';

  @override
  String get autoFullscreen => '自動全画面表示';

  @override
  String get fpsDebugOverlay => 'FPS デバッグ表示';

  @override
  String get actualCodecTiming => '実際のコーデック描画/表示タイミング';

  @override
  String get fit => 'フィット';

  @override
  String get fill => '塗りつぶし';

  @override
  String get controlPort => '制御ポート';

  @override
  String get tvAddress => 'テレビアドレス';

  @override
  String get pcConnectionInfo => 'PC 接続情報';

  @override
  String get tvIpAddress => 'TV IP アドレス';

  @override
  String get port => 'ポート';

  @override
  String get ipAddressEntryInstruction => 'PCアプリにTV IPを入力してください。';

  @override
  String get ipAddressChecking => 'IPアドレスを確認中…';

  @override
  String get networkConnectionCheck => 'ネットワーク接続を確認してください。';

  @override
  String get ipAddressLookupFailed => 'IPアドレスを確認できませんでした。しばらくしてから再確認してください。';

  @override
  String get protocol => 'プロトコル';

  @override
  String get video => '映像';

  @override
  String get fourK => '4K';

  @override
  String get decoder => 'デコーダー';

  @override
  String get surface => 'Surface';

  @override
  String get performance => 'パフォーマンス';

  @override
  String get summary => '概要';

  @override
  String get receiveDecodePresent => '受信 / デコード / 表示';

  @override
  String get presentP95 => '表示 p95';

  @override
  String get latencyAvgP95 => '遅延 平均/p95';

  @override
  String get renderer => 'レンダラー';

  @override
  String get queue => 'キュー';

  @override
  String get drops => 'ドロップ';

  @override
  String get sequenceGaps => 'シーケンス欠落';

  @override
  String get audio => '音声';

  @override
  String get audioCodec => 'コーデック';

  @override
  String get audioDecoder => 'デコーダー';

  @override
  String get track => 'トラック';

  @override
  String get audioSession => '音声セッション';

  @override
  String get queuePcm => 'キュー / PCM';

  @override
  String get buffered => 'バッファー';

  @override
  String get avSync => '音声/映像同期';

  @override
  String get avAvgP95 => '音声/映像 平均/p95';

  @override
  String get audioPackets => '音声パケット';

  @override
  String get audioWrites => '音声書き込み';

  @override
  String get audioRecovery => '音声復旧';

  @override
  String get audioReset => '音声リセット';

  @override
  String get audioExpected => '音声の想定状態';

  @override
  String get audioDrops => '音声ドロップ';

  @override
  String get audioResetReason => '音声リセット理由';

  @override
  String get audioError => '音声エラー';

  @override
  String get presentation => '表示';

  @override
  String get autoEntered => '自動移行';

  @override
  String get userExited => 'ユーザー終了';

  @override
  String get playback => '再生';

  @override
  String get scaleMode => '拡大縮小モード';

  @override
  String get display => 'ディスプレイ';

  @override
  String get videoView => '映像ビュー';

  @override
  String get aspectError => 'アスペクト比誤差';

  @override
  String get diagnostics => '診断';

  @override
  String get bytes => 'バイト';

  @override
  String get config => '設定';

  @override
  String get accessUnits => 'アクセスユニット';

  @override
  String get keyFrames => 'キーフレーム';

  @override
  String get decoderIo => 'デコーダー 入力/出力';

  @override
  String get releasedToSurface => 'Surface 出力';

  @override
  String get codecCreateRelease => 'コーデック生成/解放';

  @override
  String get surfaceLifecycle => 'Surface ライフサイクル';

  @override
  String get surfaceValid => 'Surface 有効';

  @override
  String get surfaceSize => 'Surface サイズ';

  @override
  String get surfaceZOrder => 'Surface Z 順序';

  @override
  String get configuredOutput => '構成/出力';

  @override
  String get outputCrop => '出力クロップ';

  @override
  String get lastError => '最後のエラー';

  @override
  String get receiverLog => 'レシーバーログ';

  @override
  String get state => '状態';

  @override
  String get idle => '待機';

  @override
  String get checking => '確認中';

  @override
  String get pending => '保留中';

  @override
  String get mediaCodecReady => 'MediaCodec 準備完了';

  @override
  String get surfaceViewReady => 'SurfaceView 準備完了';

  @override
  String get receiverStarting => 'レシーバーを起動しています。';

  @override
  String get receiverStartFailed => 'レシーバーを起動できませんでした。';

  @override
  String get receiverStopFailed => 'レシーバーの停止に失敗しました。';

  @override
  String get videoDebug => '映像デバッグ';

  @override
  String get renderMode => '描画モード';

  @override
  String get releaseImmediateScheduled => '即時/予約出力';

  @override
  String get input => '入力';

  @override
  String get codecRendered => 'コーデック描画';

  @override
  String get renderP50P95Max => '描画 p50/p95/max';

  @override
  String get jitterP95 => 'ジッター p95';

  @override
  String get gaps => '欠落';

  @override
  String get pts => 'PTS';

  @override
  String get drift => 'ずれ';

  @override
  String get mode => 'モード';

  @override
  String get receiverStateReady => '準備完了';

  @override
  String get receiverStateStarting => '起動中';

  @override
  String get receiverStateListening => '接続待ち';

  @override
  String get receiverStateConnecting => '接続中';

  @override
  String get receiverStateNegotiating => '接続設定中';

  @override
  String get receiverStateWaitingForSurface => '画面待ち';

  @override
  String get receiverStateWaitingForKeyFrame => '最初のフレーム待ち';

  @override
  String get receiverStateStreaming => '配信中';

  @override
  String get receiverStatePaused => '一時停止中';

  @override
  String get receiverStateResuming => '再開中';

  @override
  String get receiverStateDisconnected => '切断';

  @override
  String get receiverStateError => 'エラー';

  @override
  String get receiverStateStopping => '停止中';

  @override
  String get receiverStateRestoring => '復元中';

  @override
  String get receiverStateFailed => '失敗';

  @override
  String get statusReady => 'レシーバーの準備ができました。PC からの接続を待っています。';

  @override
  String get statusStarting => 'レシーバーを起動しています。';

  @override
  String get statusListening => 'PC からの接続を待っています。';

  @override
  String get statusConnecting => 'PC が接続され、セッションを準備しています。';

  @override
  String get statusNegotiating => '映像ストリームをネゴシエーション中です。';

  @override
  String get statusWaitingForSurface => 'テレビ画面の準備を待っています。';

  @override
  String get statusWaitingForKeyFrame => '最初の映像フレームを待っています。';

  @override
  String get statusStreaming => 'PC から映像を受信しています。';

  @override
  String get statusPaused => '再生を一時停止しています。';

  @override
  String get statusResuming => '再生を再開しています。';

  @override
  String get statusStopping => 'レシーバーセッションを停止しています。';

  @override
  String get statusRestoring => 'レシーバーのリソースを解放しています。';

  @override
  String get statusFailed => 'レシーバーエラーです。詳細はレシーバーログを確認してください。';
}
