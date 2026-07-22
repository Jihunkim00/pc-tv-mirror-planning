import 'package:flutter/material.dart';

import '../core/native_bridge/mirror_native_api.dart';
import '../features/mirroring/mirroring_page.dart';

class WindowsSenderApp extends StatelessWidget {
  const WindowsSenderApp({required this.nativeApi, super.key});

  final MirrorNativeApi nativeApi;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PC TV Mirror',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007C8A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: MirroringPage(nativeApi: nativeApi),
    );
  }
}
