import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_sender/core/localization/locale_resolution.dart';

void main() {
  group('resolveAppLocale', () {
    test('matches supported language subtags', () {
      expect(resolveAppLocale(const [Locale('ko', 'KR')]), const Locale('ko'));
      expect(resolveAppLocale(const [Locale('ja', 'JP')]), const Locale('ja'));
      expect(resolveAppLocale(const [Locale('en', 'GB')]), const Locale('en'));
    });

    test('uses the first supported locale in the system preference list', () {
      expect(
        resolveAppLocale(const [Locale('fr'), Locale('ja'), Locale('ko')]),
        const Locale('ja'),
      );
    });

    test('falls back to English when no supported locale is available', () {
      expect(resolveAppLocale(const [Locale('fr', 'FR')]), const Locale('en'));
      expect(resolveAppLocale(null), const Locale('en'));
    });
  });
}
