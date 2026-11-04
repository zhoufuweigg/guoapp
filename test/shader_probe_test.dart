import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shader filter support probe', () {
    debugPrint('PROBE isShaderFilterSupported: ${ui.ImageFilter.isShaderFilterSupported}');
    expect(true, true);
  });
}
