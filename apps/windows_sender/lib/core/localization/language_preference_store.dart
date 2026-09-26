import 'dart:io';

class LanguagePreferenceStore {
  LanguagePreferenceStore({String? path})
    : _file = File(path ?? _defaultPath());

  final File _file;

  Future<String?> load() async {
    try {
      if (!await _file.exists()) return null;
      final code = (await _file.readAsString()).trim().toLowerCase();
      if (const {'ko', 'en', 'ja'}.contains(code)) return code;
      await _file.delete();
    } catch (_) {
      // A missing or inaccessible preference falls back to the system locale.
    }
    return null;
  }

  Future<void> save(String? languageCode) async {
    try {
      if (languageCode == null) {
        if (await _file.exists()) await _file.delete();
        return;
      }
      if (!const {'ko', 'en', 'ja'}.contains(languageCode)) return;
      await _file.parent.create(recursive: true);
      await _file.writeAsString(languageCode);
    } catch (_) {
      // Keep the in-memory language choice if persistence is unavailable.
    }
  }
}

String _defaultPath() {
  final base = Platform.environment['APPDATA'];
  final root = base == null || base.isEmpty
      ? Directory.systemTemp.path
      : '$base${Platform.pathSeparator}PC to TV Mirror';
  return '$root${Platform.pathSeparator}windows_sender_language.txt';
}
