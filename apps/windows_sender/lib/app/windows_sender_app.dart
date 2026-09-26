import 'package:flutter/material.dart';
import 'package:windows_sender/l10n/generated/app_localizations.dart';

import '../core/localization/language_preference_store.dart';
import '../core/localization/locale_resolution.dart';
import '../core/native_bridge/mirror_native_api.dart';
import '../features/mirroring/mirroring_page.dart';

class WindowsSenderApp extends StatefulWidget {
  const WindowsSenderApp({
    required this.nativeApi,
    this.languageSettingsPath,
    this.preferredLocalesOverride,
    super.key,
  });

  final MirrorNativeApi nativeApi;
  final String? languageSettingsPath;
  final List<Locale>? preferredLocalesOverride;

  @override
  State<WindowsSenderApp> createState() => _WindowsSenderAppState();
}

class _WindowsSenderAppState extends State<WindowsSenderApp> {
  late final LanguagePreferenceStore _languagePreferenceStore;
  Locale? _manualLocale;
  bool _languageChanged = false;

  @override
  void initState() {
    super.initState();
    _languagePreferenceStore = LanguagePreferenceStore(
      path: widget.languageSettingsPath,
    );
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    try {
      final code = await _languagePreferenceStore.load();
      if (code == null) return;
      final locale = switch (code) {
        'ko' => const Locale('ko'),
        'en' => const Locale('en'),
        'ja' => const Locale('ja'),
        _ => null,
      };
      if (locale != null && mounted && !_languageChanged) {
        setState(() => _manualLocale = locale);
      }
    } catch (_) {
      // Language preference is best-effort; use the system locale on failure.
    }
  }

  void _setLanguagePreference(String languageCode) {
    if (languageCode == 'system') {
      _languageChanged = true;
      setState(() => _manualLocale = null);
      _clearLanguagePreference();
      return;
    }
    final locale = switch (languageCode) {
      'ko' => const Locale('ko'),
      'en' => const Locale('en'),
      'ja' => const Locale('ja'),
      _ => null,
    };
    if (locale == null) return;
    _languageChanged = true;
    setState(() => _manualLocale = locale);
    _persistLanguagePreference(languageCode);
  }

  Future<void> _persistLanguagePreference(String languageCode) async {
    try {
      await _languagePreferenceStore.save(languageCode);
    } catch (_) {
      // Keep the in-memory language choice even if settings cannot be saved.
    }
  }

  Future<void> _clearLanguagePreference() async {
    try {
      await _languagePreferenceStore.save(null);
    } catch (_) {
      // Keep the in-memory system locale if settings cannot be removed.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PC to TV Mirror',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedAppLocales,
      locale: _manualLocale,
      localeListResolutionCallback: (preferredLocales, supportedLocales) =>
          _manualLocale ??
          resolveAppLocale(widget.preferredLocalesOverride ?? preferredLocales),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007C8A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: MirroringPage(
        nativeApi: widget.nativeApi,
        languagePreferenceCode: _manualLocale?.languageCode ?? 'system',
        onLanguagePreferenceChanged: _setLanguagePreference,
      ),
    );
  }
}
