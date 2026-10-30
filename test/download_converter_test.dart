import 'dart:async';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/diary_service.dart';
import 'package:duanju_app/download_converter.dart';
import 'package:duanju_app/download_overview.dart';
import 'package:duanju_app/media_pipeline.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _ConvertingRepository extends FakeRepository {
  final begun = <String>[];
  final finished = <String>[];
  final failingBegins = <String>{};

  @override
  Future<DownloadConversion> beginConversion(String id) async {
    begun.add(id);
    if (failingBegins.contains(id)) throw AppFailure('下载文件不完整');
    return (
      input: id.endsWith(':1') ? '/work/$id/media.mp4' : '/work/$id/index.m3u8',
      key: id.endsWith(':1') ? 'abcd' : '',
      output: '/work/$id/.convert.mp4',
    );
  }

  @override
  Future<void> finishConversion(String id, String result) async {
    finished.add('$id|$result');
    if (result != 'done') return;
    jobs = [
      for (final job in jobs!)
        job.id == id
            ? downloadJob(job.drama, job.episode.number, created: job.created)
            : job,
    ];
  }
}

class _Executor implements MediaExecutor {
  final runs = <List<String>>[];
  final progress = <void Function(double)?>[];
  Completer<void>? running;
  int cancels = 0;

  @override
  Future<MediaProbe> probe(String file) async => MediaProbe({
    'format': {'duration': '12'},
    'streams': [
      {'codec_type': 'video', 'codec_name': 'h264'},
    ],
  });

  @override
  Future<void> run(
    List<String> arguments, {
    double duration = 0,
    void Function(double)? progress,
  }) {
    runs.add(arguments);
    this.progress.add(progress);
    return (running = Completer<void>()).future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final current = running;
    if (current != null && !current.isCompleted) {
      current.completeError(AppFailure('已取消本地媒体处理'));
    }
  }

  void finish([Object? error]) {
    final current = running!;
    error == null ? current.complete() : current.completeError(error);
  }
}

void main() {
  final show = drama('a', title: '剧甲');

  Future<(DownloadOverview, DownloadConverter)> start(
    _ConvertingRepository repository,
    _Executor executor,
  ) async {
    final overview = DownloadOverview(
      repository,
      await openStore(),
      interval: const Duration(hours: 1),
    );
    addTearDown(overview.dispose);
    final converter = DownloadConverter(
      repository,
      overview,
      executor: executor,
    );
    addTearDown(converter.dispose);
    await pumpEventQueue();
    return (overview, converter);
  }

  test('converts finished downloads one at a time in queue order', () async {
    final repository = _ConvertingRepository()
      ..jobs = [
        downloadJob(show, 2, state: 'converting', created: 1),
        downloadJob(show, 1, state: 'converting', created: 1),
        downloadJob(show, 3, state: 'downloading', progress: .4, created: 2),
      ];
    final executor = _Executor();
    final (_, converter) = await start(repository, executor);

    expect(repository.begun, ['hongguo:a:1']);
    expect(executor.runs.single, [
      '-decryption_key',
      'abcd',
      '-i',
      '/work/hongguo:a:1/media.mp4',
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      '/work/hongguo:a:1/.convert.mp4',
    ]);
    executor.progress.single!(.5);
    expect(converter.progressOf('hongguo:a:1'), .5);
    expect(converter.progressOf('hongguo:a:2'), isNull);

    executor.finish();
    await pumpEventQueue();
    expect(repository.finished, ['hongguo:a:1|done']);
    expect(repository.begun, ['hongguo:a:1', 'hongguo:a:2']);
    expect(executor.runs.last.take(5), [
      '-allowed_extensions',
      'ALL',
      '-extension_picky',
      '0',
      '-i',
    ]);
  });

  test('a failed conversion is reported and logged', () async {
    final repository = _ConvertingRepository()
      ..jobs = [downloadJob(show, 1, state: 'converting')];
    final executor = _Executor();
    await start(repository, executor);

    executor.finish(AppFailure('本地媒体处理失败（1），原分集已保留。'));
    await pumpEventQueue();
    expect(repository.finished, ['hongguo:a:1|failed']);
    expect(DiaryService.entries.last, contains('剧甲 第 1 集转换失败'));
  });

  test('removing the episode cancels its conversion', () async {
    final repository = _ConvertingRepository()
      ..jobs = [downloadJob(show, 1, state: 'converting')];
    final executor = _Executor();
    final (overview, _) = await start(repository, executor);

    repository.jobs = [];
    await overview.refresh();
    await pumpEventQueue();
    expect(executor.cancels, 1);
    expect(repository.finished, ['hongguo:a:1|cancel']);
  });

  test('an episode that cannot start is not retried in a loop', () async {
    final repository = _ConvertingRepository()
      ..jobs = [downloadJob(show, 2, state: 'converting')]
      ..failingBegins.add('hongguo:a:2');
    final executor = _Executor();
    final (overview, _) = await start(repository, executor);
    await overview.refresh();
    await pumpEventQueue();

    expect(repository.begun, ['hongguo:a:2']);
    expect(repository.finished, ['hongguo:a:2|cancel']);
    expect(executor.runs, isEmpty);
  });
}
