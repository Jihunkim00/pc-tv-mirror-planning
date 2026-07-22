import 'package:flutter/material.dart';

import 'app/android_tv_receiver_app.dart';
import 'core/native_bridge/receiver_native_api.dart';

void main() {
  runApp(
    const AndroidTvReceiverApp(nativeApi: MethodChannelReceiverNativeApi()),
  );
}
