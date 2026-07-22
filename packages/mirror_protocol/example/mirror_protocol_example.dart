import 'package:mirror_protocol/mirror_protocol.dart';

void main() {
  const request = StreamStartRequest(
    sessionId: 'dev-session',
    sourceType: SourceType.display,
    sourceId: r'\\.\DISPLAY1',
    video: VideoProfile.stageOne720p30(),
  );

  print(request.toJson());
}
