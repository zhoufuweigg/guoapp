import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

Future<Color?> readSystemColor() async {
  try {
    if (Platform.isAndroid) {
      final palette = await DynamicColorPlugin.getCorePalette();
      return palette == null ? null : Color(palette.primary.get(40));
    }
    if (Platform.isWindows || Platform.isMacOS) {
      return await DynamicColorPlugin.getAccentColor();
    }
  } catch (_) {}
  return null;
}
