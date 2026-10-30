import 'package:duanju_app/follow_list.dart';
import 'package:duanju_app/follow_updater.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('sources list only those with follows, in site order', () {
    final follows = [drama('a'), drama('b'), drama('c', source: 'huangdou')];
    expect(followedSources(follows).map((site) => site.id), [
      'hongguo',
      if (SourceSite.isAvailable('huangdou')) 'huangdou',
    ]);
    expect(followedSources(const []), isEmpty);
  });

  test('titles match ignoring case, width and punctuation', () {
    final item = drama('a', title: '霸道总裁 · Love');
    expect(matchesFollowTitle(item, ''), isTrue);
    expect(matchesFollowTitle(item, '总裁love'), isTrue);
    expect(matchesFollowTitle(item, 'ＬＯＶＥ'), isTrue);
    expect(matchesFollowTitle(item, '王爷'), isFalse);
  });

  test('titles match pinyin initials', () {
    final item = drama('a', title: '霸道总裁 · Love');
    expect(matchesFollowTitle(item, 'BDZC'), isTrue);
    expect(matchesFollowTitle(item, 'zclove'), isTrue);
    expect(matchesFollowTitle(item, 'wy'), isFalse);
  });

  test('the update check covers every unfinished follow', () async {
    final store = await openStore();
    final repository = FakeRepository();
    final ongoing = drama('a');
    final finished = Drama(
      id: 'hongguo:b',
      source: 'hongguo',
      title: 'b',
      episodes: 80,
      releaseStatus: 'finished',
    );
    for (final item in [ongoing, finished]) {
      await store.toggleFavorite(item);
      repository.details[item.id] = dramaDetail(
        Drama(
          id: item.id,
          source: 'hongguo',
          title: item.title,
          episodes: 90,
          releaseStatus: item.releaseStatus,
        ),
      );
    }

    final updater = FollowUpdater(repository, store);
    addTearDown(updater.dispose);
    await updater.run();
    expect(repository.detailRequests, 1);
    expect(store.following(ongoing.id)?.newEpisodes, 10);
    expect(store.following(finished.id)?.hasUpdates, isFalse);
  });
}
