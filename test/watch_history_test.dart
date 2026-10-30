import 'package:duanju_app/watch_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('periods split at local midnight', () {
    final now = DateTime(2026, 10, 23, 9);
    expect(WatchPeriod.of(DateTime(2026, 10, 23), now), WatchPeriod.today);
    expect(
      WatchPeriod.of(DateTime(2026, 10, 22, 23, 59), now),
      WatchPeriod.yesterday,
    );
    expect(WatchPeriod.of(DateTime(2026, 10, 22), now), WatchPeriod.yesterday);
    expect(
      WatchPeriod.of(DateTime(2026, 10, 21, 23, 59), now),
      WatchPeriod.earlier,
    );
    expect(
      WatchPeriod.of(DateTime(2026, 11, 1), DateTime(2026, 11, 2)),
      WatchPeriod.yesterday,
    );
  });

  test('titles match ignoring case, width and punctuation', () {
    final entry = watching(drama('a', title: '霸道总裁 · Love'));
    expect(matchesWatchTitle(entry, ''), isTrue);
    expect(matchesWatchTitle(entry, '总裁love'), isTrue);
    expect(matchesWatchTitle(entry, 'ＬＯＶＥ'), isTrue);
    expect(matchesWatchTitle(entry, '王爷'), isFalse);
  });

  test('titles match pinyin initials', () {
    final entry = watching(drama('a', title: '霸道总裁 · Love'));
    expect(matchesWatchTitle(entry, 'BDZC'), isTrue);
    expect(matchesWatchTitle(entry, 'wy'), isFalse);
  });
}
