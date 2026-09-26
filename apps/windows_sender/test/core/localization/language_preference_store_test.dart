import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:windows_sender/core/localization/language_preference_store.dart';

void main() {
  late Directory tempDirectory;
  late File preferenceFile;
  late LanguagePreferenceStore store;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'windows_sender_language_test_',
    );
    preferenceFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}language.txt',
    );
    store = LanguagePreferenceStore(path: preferenceFile.path);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('persists and reloads a supported language, then clears it', () async {
    expect(await store.load(), isNull);

    await store.save('ja');
    expect(await preferenceFile.readAsString(), 'ja');
    expect(await store.load(), 'ja');

    await store.save(null);
    expect(await preferenceFile.exists(), isFalse);
    expect(await store.load(), isNull);
  });

  test('invalid saved language falls back to system and is cleared', () async {
    await preferenceFile.writeAsString('fr');

    expect(await store.load(), isNull);
    expect(await preferenceFile.exists(), isFalse);
  });
}
