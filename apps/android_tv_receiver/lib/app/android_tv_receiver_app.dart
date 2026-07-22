import 'package:flutter/material.dart';

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
      title: 'PC TV Mirror',
      debugShowCheckedModeBanner: false,
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
