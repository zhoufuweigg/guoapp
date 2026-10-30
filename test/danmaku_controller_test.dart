import 'dart:async';
import 'dart:math' as math;

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/danmaku_controller.dart';
import 'package:duanju_app/danmaku_models.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _Request {
  _Request(this.plan, this.startMs, this.durationMs);
  final PlaybackPlan plan;
  final int startMs;
  final int durationMs;
  final result = Completer<DanmakuPage>();
}

class _DanmakuRepository extends FakeRepository {
  final calls = <_Request>[];
  bool hold = false;
  bool fail = false;
  int cancellations = 0;
  DanmakuPage Function(_Request)? response;

  static DanmakuPage page(_Request request) => DanmakuPage(
    episodeId: request.plan.danmakuId,
    startMs: request.startMs,
    nextMs: math.min(request.startMs + danmakuWindowMs, request.durationMs),
    items: [
      DanmakuItem(
        id: '${request.plan.danmakuId}-${request.startMs}',
        text: '合成弹幕 ${request.plan.danmakuId}',
        timeMs: request.startMs,
      ),
    ],
  );

  @override
  Future<DanmakuPage> danmaku(
    PlaybackPlan plan, {
    required int startMs,
    required int durationMs,
  }) async {
    final request = _Request(plan, startMs, durationMs);
    calls.add(request);
    if (hold) return request.result.future;
    if (fail) throw AppFailure('合成弹幕失败');
    return response?.call(request) ?? page(request);
  }

  @override
  Future<void> cancelDanmaku() async {
    cancellations++;
  }
}

const _plan = PlaybackPlan(
  url: 'https://media.example.test/synthetic.mp4',
  session: 'current',
  danmakuId: '1001',
);

void _update(
  DanmakuController controller, {
  int position = 0,
  int duration = 180000,
  bool playing = true,
  bool buffering = false,
  bool foreground = true,
  double speed = 1,
}) {
  controller.update(
    position: Duration(milliseconds: position),
    duration: Duration(milliseconds: duration),
    speed: speed,
    playing: playing,
    buffering: buffering,
    foreground: foreground,
    available: true,
  );
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.value();
  }
}

DanmakuController _open(
  _DanmakuRepository repository, {
  DateTime Function()? now,
}) {
  final controller = DanmakuController(repository, now: now)..setPlan(_plan);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test('pages keep zero timestamps and text and reject unverified items', () {
    final json = <String, dynamic>{
      'episodeId': '1001',
      'startMs': 0,
      'nextMs': 30000,
      'items': [
        {'id': 'literal', 'text': '<b>文字</b>\n第二行', 'timeMs': 0},
        {'id': 'later', 'text': '下一条', 'timeMs': 15000},
        {'id': 'literal', 'text': '重复', 'timeMs': 1},
        {'id': 'fraction', 'text': '无效', 'timeMs': 1.2},
        {'id': 'missing', 'text': '普通评论'},
        {'id': 'outside', 'text': '越界', 'timeMs': 30000},
      ],
    };
    DanmakuPage parse(Map<String, dynamic> value) => DanmakuPage.fromJson(
      value,
      episodeId: '1001',
      startMs: 0,
      durationMs: 60000,
    );
    final page = parse(json);
    expect(page.items.map((item) => item.timeMs), [0, 15000]);
    expect(page.items.first.text, '<b>文字</b> 第二行');
    for (final invalid in [
      {...json, 'episodeId': 'other'},
      {...json, 'startMs': 1},
      {...json, 'nextMs': 0},
      {...json, 'nextMs': 60001},
      {...json, 'nextMs': 30000.0},
      {...json, 'items': null},
    ]) {
      expect(() => parse(invalid), throwsFormatException);
    }
    expect(parse({...json, 'items': []}).items, isEmpty);
  });

  test('windows load one at a time and follow the source cursor', () async {
    final repository = _DanmakuRepository()..hold = true;
    final controller = _open(repository);
    _update(controller);
    _update(controller, position: 1000);
    expect(repository.calls, hasLength(1));
    repository.calls.first.result.complete(
      DanmakuPage(
        episodeId: '1001',
        startMs: 0,
        nextMs: 12000,
        items: const [],
      ),
    );
    await _flush();
    _update(controller, position: 5000);
    expect(repository.calls.last.startMs, 12000);
    _update(controller, position: 5100);
    expect(repository.calls, hasLength(2));
  });

  test('short windows catch up to a seek without repeating', () async {
    final repository = _DanmakuRepository()
      ..response = (request) => DanmakuPage(
        episodeId: request.plan.danmakuId,
        startMs: request.startMs,
        nextMs: request.startMs + 1000,
        items: const [],
      );
    final controller = _open(repository);
    _update(controller, position: 20000, playing: false);
    await _flush();
    expect(repository.calls.map((call) => call.startMs), [0, 20000]);
    expect(controller.loading, isFalse);
  });

  test('episode changes, disabling and disposal drop late responses', () async {
    final repository = _DanmakuRepository()..hold = true;
    final controller = DanmakuController(repository)..setPlan(_plan);
    _update(controller);
    final first = repository.calls.single;
    controller.setPlan(
      const PlaybackPlan(
        url: 'https://media.example.test/second.mp4',
        session: 'next',
        danmakuId: '1002',
      ),
    );
    _update(controller);
    final second = repository.calls.last;
    first.result.complete(_DanmakuRepository.page(first));
    await _flush();
    expect(controller.items, isEmpty);
    expect(repository.cancellations, 1);
    controller.setEnabled(false);
    second.result.complete(_DanmakuRepository.page(second));
    await _flush();
    expect(controller.items, isEmpty);
    expect(controller.visible, isFalse);
    controller.setEnabled(true);
    final third = repository.calls.last;
    controller.dispose();
    third.result.completeError(StateError('late failure'));
    await _flush();
    expect(repository.cancellations, 3);
  });

  test('local and unsupported plans make no requests', () async {
    final repository = _DanmakuRepository();
    final controller = DanmakuController(repository);
    addTearDown(controller.dispose);
    for (final plan in [
      const PlaybackPlan(
        url: 'file:///synthetic.mp4',
        local: true,
        session: 'local',
        danmakuId: '1001',
      ),
      const PlaybackPlan(
        url: 'https://media.example.test/other.mp4',
        session: 'other',
      ),
    ]) {
      controller.setPlan(plan);
      _update(controller);
      expect(controller.visible, isFalse);
    }
    await _flush();
    expect(repository.calls, isEmpty);
  });

  test(
    'pausing and buffering stop motion; background cancels loading',
    () async {
      final repository = _DanmakuRepository()..hold = true;
      final controller = _open(repository);
      _update(controller, buffering: true);
      expect(repository.calls, isEmpty);
      expect(controller.moving, isFalse);
      _update(controller, playing: false);
      expect(repository.calls, hasLength(1));
      expect(controller.moving, isFalse);
      _update(controller, foreground: false);
      expect(repository.cancellations, 1);
      expect(controller.visible, isFalse);
      final old = repository.calls.single;
      old.result.complete(_DanmakuRepository.page(old));
      await _flush();
      expect(controller.items, isEmpty);
      _update(controller);
      expect(repository.calls, hasLength(2));
      controller.beginSeek();
      expect(controller.visible, isFalse);
      final stale = repository.calls.last;
      stale.result.complete(_DanmakuRepository.page(stale));
      await _flush();
      controller.endSeek(const Duration(seconds: 65));
      expect(repository.calls.last.startMs, 60000);
    },
  );

  test('failed windows back off and then retry', () async {
    var now = DateTime(2026);
    final repository = _DanmakuRepository()..fail = true;
    final controller = _open(repository, now: () => now);
    _update(controller);
    await _flush();
    expect(controller.canRetry, isTrue);
    for (var i = 0; i < 10; i++) {
      _update(controller, position: i * 100);
    }
    expect(repository.calls, hasLength(1));
    now = now.add(const Duration(seconds: 16));
    repository.fail = false;
    _update(controller, position: 1000);
    await _flush();
    expect(repository.calls, hasLength(2));
    expect(controller.canRetry, isFalse);
    expect(controller.items, hasLength(1));
  });

  test('regular samples keep motion anchors; seeks and speed resync', () async {
    var now = DateTime(2026);
    final controller = _open(_DanmakuRepository(), now: () => now);
    _update(controller);
    await _flush();
    final initial = controller.motionRevision;
    for (var i = 1; i <= 4; i++) {
      now = now.add(const Duration(milliseconds: 250));
      _update(controller, position: i * 250);
    }
    expect(controller.motionRevision, initial);
    _update(controller, position: 1000, speed: 3);
    expect(controller.motionRevision, initial + 1);
    now = now.add(const Duration(milliseconds: 500));
    _update(controller, position: 2500, speed: 3);
    expect(controller.motionRevision, initial + 1);
    controller.beginSeek();
    controller.endSeek(const Duration(milliseconds: 3000));
    expect(controller.motionRevision, initial + 3);
    _update(controller, position: 3000, playing: false, speed: 3);
    expect(controller.moving, isFalse);
  });

  test('long playback keeps only nearby windows', () async {
    final repository = _DanmakuRepository();
    final controller = _open(repository);
    for (var page = 0; page < 25; page++) {
      _update(
        controller,
        position: page * 30000,
        duration: 1800000,
        playing: false,
      );
      await _flush();
      expect(controller.items.length, lessThanOrEqualTo(6));
    }
    expect(controller.items.first.timeMs, greaterThan(0));
    expect(repository.calls, hasLength(25));
  });
}
