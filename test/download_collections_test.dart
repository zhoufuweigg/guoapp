import 'package:duanju_app/download_collections.dart';
import 'package:duanju_app/download_preferences.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  final first = drama('a', title: '剧甲');
  final second = drama('b', source: 'hanxiaoquan', title: '剧乙');

  test('pending downloads keep queue order and skip removals', () {
    final jobs = [
      downloadJob(first, 3, state: 'paused', created: 20),
      downloadJob(first, 1, created: 5),
      downloadJob(second, 2, state: 'failed', created: 10),
      downloadJob(first, 2, state: 'queued', created: 20),
      downloadJob(second, 9, state: 'removing', created: 1),
    ];

    expect(
      [for (final job in pendingDownloads(jobs)) job.id],
      ['${second.id}:2', '${first.id}:2', '${first.id}:3'],
    );
  });

  test('downloaded dramas group finished episodes, newest first', () {
    final renamed = drama('a', title: '剧甲新名');
    final jobs = [
      downloadJob(first, 2, bytes: 200, created: 1),
      downloadJob(renamed, 1, bytes: 100, created: 3),
      downloadJob(first, 3, state: 'downloading', created: 4),
      downloadJob(second, 1, bytes: 50, created: 2),
      downloadJob(second, 2, state: 'removing', created: 5),
    ];

    final dramas = downloadedDramas(jobs);

    expect([for (final item in dramas) item.drama.title], ['剧甲新名', '剧乙']);
    expect(
      [for (final job in dramas.first.episodes) job.episode.number],
      [1, 2],
    );
    expect(dramas.first.bytes, 300);
    expect(dramas.first.pending, 1);
    expect(dramas.last.pending, 0);
  });

  test('sources and marks only describe the jobs present', () {
    final jobs = [
      downloadJob(second, 1),
      downloadJob(second, 2, state: 'queued'),
      downloadJob(second, 3, state: 'removing'),
      downloadJob(first, 4),
    ];

    expect(downloadSources(jobs), [
      for (final site in SourceSite.values)
        if (site.id == 'hongguo' || site.id == 'hanxiaoquan') site,
    ]);
    final marks = downloadMarks(jobs, second.id);
    expect(marks.downloaded, {1});
    expect(marks.downloading, {2});
  });

  test('enqueue uses the saved quality and splits large selections', () async {
    final repository = FakeRepository();
    final store = await openStore();
    await store.setDownloadPreferences(const DownloadPreferences(quality: 720));
    final detail = dramaDetail(first, count: 1200);

    final added = await enqueueEpisodes(
      repository,
      store,
      detail,
      detail.episodes,
    );

    expect(added, 1200);
    expect(
      [for (final call in repository.enqueued) call.episodes.length],
      [500, 500, 200],
    );
    expect(repository.enqueued.map((call) => call.quality).toSet(), {720});
    expect(repository.enqueued.last.episodes.last, 1200);
  });

  test('filling counts missing episodes before queueing them', () async {
    final repository = FakeRepository()
      ..details[first.id] = dramaDetail(first, count: 10, vip: {9, 10});
    final store = await openStore();
    await store.setDownloadPreferences(const DownloadPreferences(quality: 480));
    final updater = DownloadCollectionUpdater(repository, store);
    addTearDown(updater.dispose);

    final plan = await updater.inspect(first, [
      downloadJob(first, 1),
      downloadJob(first, 2),
      downloadJob(first, 3, state: 'failed'),
      downloadJob(first, 4, state: 'queued'),
      downloadJob(first, 5, state: 'removing'),
      downloadJob(second, 6),
    ]);

    expect(plan.missing, 5);
    expect(plan.skippedVip, 2);
    expect(repository.enqueued, isEmpty);

    await updater.fill(plan);

    expect(updater.error, isNull);
    expect(repository.enqueued.single.episodes, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(repository.enqueued.single.quality, 480);
  });

  test('batch control collects failures without stopping', () async {
    final repository = FakeRepository()..failingControls.add('b');

    final result = await controlDownloadJobs(repository, 'remove', [
      'a',
      'b',
      'c',
    ]);

    expect(result.completed, ['a', 'c']);
    expect(result.failures.keys, ['b']);
    expect(repository.controls, ['remove|a', 'remove|c']);
  });
}
