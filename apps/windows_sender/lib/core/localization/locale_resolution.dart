import 'package:flutter/widgets.dart';

const supportedAppLocales = <Locale>[Locale('ko'), Locale('en'), Locale('ja')];

Locale resolveAppLocale(List<Locale>? preferredLocales) {
  for (final locale in preferredLocales ?? const <Locale>[]) {
    switch (locale.languageCode.toLowerCase()) {
      case 'ko':
        return const Locale('ko');
      case 'en':
        return const Locale('en');
      case 'ja':
        return const Locale('ja');
    }
  }
  return const Locale('en');
}
