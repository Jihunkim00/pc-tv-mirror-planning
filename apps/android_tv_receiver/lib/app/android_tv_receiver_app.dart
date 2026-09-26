import 'package:flutter/material.dart';
import 'package:android_tv_receiver/l10n/generated/app_localizations.dart';

import '../core/localization/locale_resolution.dart';
import '../core/native_bridge/receiver_native_api.dart';
import '../features/receiver/receiver_home_page.dart';

class AndroidTvReceiverApp extends StatelessWidget {
  const AndroidTvReceiverApp({
    required this.nativeApi,
    this.showNativeSurface = true,
    super.key,
  });

  final ReceiverNativeApi nativeApi;
  final bool showNativeSurface;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PC to TV Mirror',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedAppLocales,
      localeListResolutionCallback: (preferredLocales, supportedLocales) =>
          resolveAppLocale(preferredLocales),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A3A3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ReceiverHomePage(
        nativeApi: nativeApi,
        showNativeSurface: showNativeSurface,
      ),
    );
  }
}
