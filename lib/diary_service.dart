import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class DiaryService {
  static final List<String> _entries = <String>[];
  static const int maxEntries = 500;
  static String? nativeLogPath;
  static String _nativeText = '';
  static int _clears = 0;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void add(String message) {
    final entry = '[${_clock(DateTime.now())}] $message';
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    revision.value++;
    debugPrint('[Diary] $message');
  }

  static List<String> get entries => List<String>.unmodifiable([
    ..._entries,
    if (_nativeText.isNotEmpty) ..._nativeText.split('\n'),
  ]);

  static Future<void> clear() async {
    _entries.clear();
    _nativeText = '';
    _clears++;
    revision.value++;
    final path = nativeLogPath;
    if (path == null) return;
    for (final name in [path, '$path.1', '$path.2']) {
      try {
        await File(name).delete();
      } on FileSystemException {
        continue;
      }
    }
  }

  static String get fullText => [_entries.join('\n'), _nativeText].join('\n');

  static Future<void> refreshNativeLogs() async {
    final path = nativeLogPath;
    if (path == null) return;
    final clears = _clears;
    final lines = <String>[];
    for (final name in ['$path.1', path]) {
      RandomAccessFile? file;
      try {
        file = await File(name).open();
        final size = await file.length();
        final start = size > 128 * 1024 ? size - 128 * 1024 : 0;
        await file.setPosition(start);
        final text = utf8.decode(
          await file.read(size - start),
          allowMalformed: true,
        );
        for (final line in text.split('\n').skip(start > 0 ? 1 : 0)) {
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            final name = event['event'] as String? ?? '';
            if (name.startsWith('stream.')) {
              lines.add(_nativeLine(event, name.substring('stream.'.length)));
            }
          } catch (_) {}
        }
      } on FileSystemException {
        continue;
      } finally {
        await file?.close();
      }
    }
    if (clears != _clears) return;
    _nativeText = lines
        .skip(lines.length > 500 ? lines.length - 500 : 0)
        .join('\n');
  }

  static String _nativeLine(Map<String, dynamic> event, String name) {
    final time = DateTime.parse(event['time'] as String).toLocal();
    final status = event['httpStatus'];
    return [
      '[${_clock(time)}] [Stream] $name',
      event['host'],
      if (status != null) 'HTTP $status',
      event['responseType'],
      event['message'],
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
  }

  static String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${time.millisecond ~/ 100}';
}
