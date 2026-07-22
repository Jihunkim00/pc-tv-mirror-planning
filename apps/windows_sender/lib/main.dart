import 'package:flutter/material.dart';

import 'app/windows_sender_app.dart';
import 'core/native_bridge/mirror_native_api.dart';

void main() {
  runApp(const WindowsSenderApp(nativeApi: MethodChannelMirrorNativeApi()));
}
