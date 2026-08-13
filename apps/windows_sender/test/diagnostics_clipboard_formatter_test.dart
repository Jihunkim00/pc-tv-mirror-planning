import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

import 'package:windows_sender/features/mirroring/diagnostics_clipboard_formatter.dart';

void main() {
  test(
    'formats all required sections and unavailable values without a snapshot',
    () {
      final text = DiagnosticsClipboardFormatter.format(
        snapshot: null,
        sourceDisplay: null,
        sessionId: null,
      );

      for (final section in [
        '=== SESSION ===',
        'SOURCE DISPLAY',
        'CAPTURE',
        'ENCODER',
        'TRANSPORT',
        'RECEIVER',
        'VIDEO TIMING',
        'AUDIO',
        'PIPELINE',
        'DEBUG',
      ]) {
        expect(text, contains(section));
      }
      expect(text, contains('unavailable'));
      expect(text, contains('receiverMetricsSource:'));
    },
  );

  test('includes immutable source display information', () {
    final text = DiagnosticsClipboardFormatter.format(
      snapshot: null,
      sourceDisplay: const DisplayInfo(
        id: 'display-1',
        name: 'Panel',
        width: 1920,
        height: 1080,
        x: 0,
        y: 0,
        scaleFactor: 1,
        isPrimary: true,
        refreshRateHz: 60,
      ),
      sessionId: 'session-1',
    );

    expect(text, contains('session-1'));
    expect(text, contains('1920x1080@60.00 Hz Panel'));
  });
}
