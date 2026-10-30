import 'package:flutter/services.dart';

class NativeTextInput {
  static const _channel = MethodChannel('duanju/text_input');

  static void start(
    String text, {
    required void Function(String text) onChanged,
    required void Function(String text, bool submit) onDone,
  }) {
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      switch (call.method) {
        case 'changed' when arguments is String:
          onChanged(arguments);
        case 'done' when arguments is Map:
          _channel.setMethodCallHandler(null);
          final text = arguments['text'];
          onDone(text is String ? text : '', arguments['submit'] == true);
      }
    });
    _channel.invokeMethod<void>('start', {'text': text}).catchError((_) {
      _channel.setMethodCallHandler(null);
      onDone(text, false);
    });
  }

  static void stop() {
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod<void>('stop').catchError((_) {});
  }
}
