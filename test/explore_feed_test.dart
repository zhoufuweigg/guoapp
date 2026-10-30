import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/explore_feed.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<ExploreFeed> _open(
  FakeRepository repository, [
  Future<void> Function(LocalStore store)? prepare,
]) async {
  final store = await openStore();
  await prepare?.call(store);
  final explore = ExploreFeed(repository, store);
  addTearDown(explore.dispose);
  await pumpEventQueue();
  return explore;
}

List<String> _titles(ExploreFeed explore) => [
  for (final item in explore.items) item.title,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hongguo opens on picks with the first one featured', () async {
    final explore = await _open(FakeRepository());
    expect(explore.source?.id, 'hongguo');
    expect(
      [for (final tab in explore.tabs) tab.id],
      [recommendTab.id, '', 'short_play'],
    );
    expect(explore.recommending, isTrue);
    expect(explore.featured?.title, '推荐剧一');
    expect(_titles(explore), ['推荐剧二', '推荐剧三']);
  });

  test('recent watching takes the lead on the first tab only', () async {
    final explore = await _open(
      FakeRepository(),
      (store) => store.saveWatch(watching(drama('w'), episode: 4)),
    );
    expect(explore.resume?.episode, 4);
    expect(explore.featured, isNull);
    expect(_titles(explore), ['推荐剧一', '推荐剧二', '推荐剧三']);

    explore.select('short_play');
    await pumpEventQueue();
    expect(explore.resume, isNull);
    expect(_titles(explore), ['分类short_play']);
  });

  test('refresh forces the current tab only', () async {
    final repository = FakeRepository();
    final explore = await _open(repository);
    await explore.refresh();
    expect(repository.recommendRequests.last, (more: false, force: true));

    explore.select('short_play');
    await pumpEventQueue();
    await explore.refresh();
    expect(repository.catalogRequests, [
      'hongguo|short_play||1',
      'hongguo|short_play||1!',
    ]);
  });

  test('ranking boards of this source follow all, with their ranks', () async {
    final repository = FakeRepository()
      ..boardList = const [
        RankingBoard(id: 'hongguo-hot', source: 'hongguo', name: '总热播榜'),
        RankingBoard(id: 'huangdou-all', source: 'huangdou', name: '总榜'),
      ];
    final explore = await _open(repository);
    final tabs = explore.tabs;
    expect([for (final tab in tabs) tab.name], ['推荐', '全部', '总热播榜', '真人剧']);
    expect(explore.resume, isNull);

    explore.select(tabs[2].id);
    await pumpEventQueue();
    expect(explore.featured, isNull);
    expect(_titles(explore), ['hongguo-hot第1名', 'hongguo-hot第2名']);
    await explore.feed!.loadMore();
    expect(
      [for (final item in explore.items) explore.rankOf(item)],
      [1, 2, 3, 4],
    );
    await explore.refresh();
    expect(repository.rankingRequests, [
      'hongguo-hot|1',
      'hongguo-hot|2',
      'hongguo-hot|1!',
    ]);

    explore.select('short_play');
    await pumpEventQueue();
    expect(explore.rankOf(explore.items.single), isNull);
  });

  test('turning the source off moves on, then back when it returns', () async {
    late LocalStore store;
    final explore = await _open(FakeRepository(), (value) async {
      store = value;
    });
    await store.setSourceEnabled('hongguo', false);
    await pumpEventQueue();
    expect(explore.source?.id, allSourcesEnabled ? 'hanxiaoquan' : null);
    expect(explore.feed == null, !allSourcesEnabled);

    await store.setSourceEnabled('hongguo', true);
    await pumpEventQueue();
    expect(explore.source?.id, 'hongguo');
    expect(explore.featured?.title, '推荐剧一');
  });

  test('loaded and updated dramas refresh saved records', () async {
    final repository = FakeRepository();
    late LocalStore store;
    final explore = await _open(repository, (value) async {
      store = value;
      await store.toggleFavorite(drama('r1', title: '旧名'));
    });
    expect(store.favorites.single.title, '推荐剧一');

    repository.catalogUpdates.publish(drama('r2', title: '新名'));
    await pumpEventQueue();
    expect(_titles(explore), ['新名', '推荐剧三']);
  });
}
