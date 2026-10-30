import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/download_merge.dart';
import 'package:duanju_app/media_pipeline.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _LocalRepository extends FakeRepository {
  @override
  Future<PlaybackPlan?> localPlayback(Drama drama, Episode episode) async =>
      PlaybackPlan(url: '/videos/${episode.number}.mp4', local: true);
}

class _Executor implements MediaExecutor {
  final heights = <String, int>{};
  final runs = <List<String>>[];

  @override
  Future<MediaProbe> probe(String file) async => MediaProbe({
    'format': {'duration': '12'},
    'streams': [
      {'codec_type': 'video', 'codec_name': 'h264', 'height': heights[file]},
      {'codec_type': 'audio', 'codec_name': 'aac', 'sample_rate': '44100'},
    ],
  });

  @override
  Future<void> run(
    List<String> arguments, {
    double duration = 0,
    void Function(double)? progress,
  }) async => runs.add(arguments);

  @override
  Future<void> cancel() async {}
}

void main() {
  final show = drama('a', title: '剧甲');

  test('episode numbers collapse into ranges', () {
    expect(episodeRanges([1, 2, 3, 5, 7, 8, 9]), '1-3、5、7-9');
    expect(episodeRanges([4]), '4');
  });

  test('file names keep short ranges and summarize long ones', () {
    expect(mergeFileName('剧/甲', [1, 2, 3, 5]), '剧_甲 第1-3、5集.mp4');
    expect(
      mergeFileName('剧甲', [for (var i = 1; i <= 40; i += 2) i]),
      '剧甲 第1-39集等20集.mp4',
    );
  });

  test('episodes with a different format are refused', () async {
    final executor = _Executor()
      ..heights.addAll({
        '/videos/1.mp4': 1080,
        '/videos/2.mp4': 720,
        '/videos/3.mp4': 1080,
        '/videos/5.mp4': 720,
      });
    final merge = DownloadMerge(_LocalRepository(), executor: executor);
    addTearDown(merge.dispose);

    await expectLater(
      merge.prepare([
        downloadJob(show, 5),
        downloadJob(show, 1),
        downloadJob(show, 2),
        downloadJob(show, 3),
      ]),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.message,
          'message',
          startsWith('第 2、5 集的画面或声音格式和其余集不同'),
        ),
      ),
    );
  });

  test('selected episodes are concatenated in episode order', () async {
    final executor = _Executor();
    final merge = DownloadMerge(_LocalRepository(), executor: executor);
    addTearDown(merge.dispose);

    await merge.prepare([downloadJob(show, 3), downloadJob(show, 1)]);
    expect(merge.fileName, '剧甲 第1、3集.mp4');
    await merge.write('saf:1.mp4');

    final arguments = executor.runs.single;
    expect(arguments.take(4), ['-f', 'concat', '-safe', '0']);
    expect(arguments, isNot(contains('+faststart')));
    expect(arguments.last, 'saf:1.mp4');
  });
}
