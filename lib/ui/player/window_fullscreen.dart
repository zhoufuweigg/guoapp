import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_device.dart';

Future<void> setWindowFullScreen(bool value) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await AppDevice.channel.invokeMethod<void>('setFullScreen', {
        'enabled': value,
      });
    } else {
      await windowManager.setFullScreen(value);
    }
  } catch (_) {}
}
