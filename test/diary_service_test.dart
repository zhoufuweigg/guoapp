import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/diary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native stream events are shown as readable lines', () async {
    final directory = await Directory.systemTemp.createTemp('diary');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/app.log';
    final time = DateTime(2026, 10, 22, 9, 5, 7, 300);
    await File(path).writeAsString(
      [
        {
          'time': time.toUtc().toIso8601String(),
          'level': 'warning',
          'event': 'stream.upstream_status',
          'host': 'cdn.test',
          'httpStatus': 403,
          'message': 'session=abc asset=segment path=/a.ts',
        },
        {
          'time': time.toUtc().toIso8601String(),
          'level': 'error',
          'event': 'cover_failed',
          'message': 'ignored',
        },
      ].map(jsonEncode).join('\n'),
    );
    DiaryService.nativeLogPath = path;
    addTearDown(() => DiaryService.nativeLogPath = null);

    await DiaryService.refreshNativeLogs();

    expect(DiaryService.entries, [
      '[09:05:07.3] [Stream] upstream_status cdn.test HTTP 403 '
          'session=abc asset=segment path=/a.ts',
    ]);

    await DiaryService.clear();
    await DiaryService.refreshNativeLogs();

    expect(DiaryService.entries, isEmpty);
    expect(File(path).existsSync(), isFalse);
  });
}
