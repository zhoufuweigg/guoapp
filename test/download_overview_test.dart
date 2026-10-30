import 'package:duanju_app/download_overview.dart';
import 'package:duanju_app/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

DownloadOverview _watch(FakeRepository repository, LocalStore store) {
  final overview = DownloadOverview(
    repository,
    store,
    interval: const Duration(hours: 1),
  );
  addTearDown(overview.dispose);
  return overview;
}

void main() {
  final first = drama('a', title: '剧甲');
  final second = drama('b', title: '剧乙');

  test('summarizes running and finished jobs', () async {
    final repository = FakeRepository()
      ..jobs = [
        downloadJob(first, 1, bytes: 300 << 20),
        downloadJob(first, 2, state: 'queued', progress: 0),
        downloadJob(second, 5, state: 'downloading', progress: .45),
      ];
    final overview = _watch(repository, await openStore());
    await pumpEventQueue();

    expect(overview.active, 2);
    expect(overview.current?.drama.id, second.id);
    expect(overview.current?.episode.number, 5);
    expect(overview.completed, 1);
    expect(overview.completedBytes, 300 << 20);
  });

  test('notifies only when the jobs change', () async {
    final repository = FakeRepository()..jobs = [downloadJob(first, 1)];
    final overview = _watch(repository, await openStore());
    var changes = 0;
    overview.addListener(() => changes++);
    await pumpEventQueue();
    await overview.refresh();
    expect(changes, 1);

    repository.jobs = [downloadJob(first, 1, state: 'queued', progress: 0)];
    await overview.refresh();
    expect(changes, 2);
    expect(overview.active, 1);
  });

  test('users without download permission are never polled', () async {
    final repository = FakeRepository()..jobs = [downloadJob(first, 1)];
    final overview = _watch(repository, await openStore(viewerPreferences));
    await pumpEventQueue();

    expect(repository.downloadRequests, 0);
    expect(overview.completed, 0);
  });
}
