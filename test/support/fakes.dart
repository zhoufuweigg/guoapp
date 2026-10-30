import 'dart:convert';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_profiles.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:duanju_app/resource_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Drama drama(
  String key, {
  String source = 'hongguo',
  String? title,
  String category = '',
  int episodes = 80,
}) => Drama(
  id: '$source:$key',
  source: source,
  title: title ?? key,
  category: category,
  episodes: episodes,
);

WatchEntry watching(Drama drama, {int episode = 1, double position = 10}) =>
    WatchEntry(
      drama: drama,
      episode: episode,
      position: position,
      duration: 100,
      updatedAt: DateTime(2026, 10, 20),
    );

final viewerPreferences = <String, Object>{
  'profiles': jsonEncode([
    LocalProfile(
      id: 'default',
      name: '管理员',
      admin: true,
      salt: '0' * 32,
      pinHash: '1' * 64,
    ).toJson(),
    const LocalProfile(
      id: 'viewer',
      name: '访客',
      sources: ['hongguo'],
      download: false,
    ).toJson(),
  ]),
  'activeProfile': 'viewer',
};

Future<LocalStore> openStore([
  Map<String, Object> initial = const {},
  Future<String> Function(String pin, String salt)? pinHasher,
]) async {
  SharedPreferences.setMockInitialValues(Map.of(initial));
  final store = LocalStore(
    await SharedPreferences.getInstance(),
    pinHasher: pinHasher,
  );
  addTearDown(store.dispose);
  return store;
}

DownloadJob downloadJob(
  Drama drama,
  int episode, {
  String state = 'completed',
  double progress = 1,
  int bytes = 0,
  int created = 0,
}) => DownloadJob(
  id: '${drama.id}:$episode',
  drama: drama,
  episode: Episode(const {}, episode),
  state: state,
  progress: progress,
  bytes: bytes,
  created: created,
);

DramaDetail dramaDetail(
  Drama drama, {
  int count = 80,
  Set<int> vip = const {},
  String warning = '',
}) => DramaDetail(drama, [
  for (var number = 1; number <= count; number++)
    Episode({'currentEpisode': number, 'vip': vip.contains(number)}, number),
], warning: warning);

LocalStore restartStore(LocalStore store) {
  final restarted = LocalStore(store.preferences);
  addTearDown(restarted.dispose);
  return restarted;
}

class FakeRepository extends AppRepository {
  List<CatalogCategory> categoryList = const [
    CatalogCategory.all,
    CatalogCategory('short_play', '真人剧'),
  ];
  List<Drama> recommended = [
    drama('r1', title: '推荐剧一'),
    drama('r2', title: '推荐剧二'),
    drama('r3', title: '推荐剧三'),
  ];
  List<String> suggestionList = const [];
  List<RankingBoard> boardList = const [];
  final cachedPages = <String, CatalogPage>{};
  final catalogRequests = <String>[];
  final rankingRequests = <String>[];
  final recommendRequests = <({bool more, bool force})>[];
  String failure = '';
  List<DownloadJob>? jobs;
  int downloadRequests = 0;
  ResourceSettings resource = const ResourceSettings();
  final savedResources = <ResourceSettings>[];

  @override
  Future<ResourceSettings> resourceSettings() async => resource;

  @override
  Future<ResourceSettings> saveResourceSettings(
    ResourceSettings settings,
  ) async {
    savedResources.add(settings);
    return resource = settings;
  }

  @override
  bool get supportsDownloads => jobs != null;

  @override
  Future<List<DownloadJob>> downloads() async {
    downloadRequests++;
    return jobs ?? const [];
  }

  final enqueued = <({String drama, List<int> episodes, int quality})>[];
  final controls = <String>[];
  final failingControls = <String>{};

  @override
  Future<int> enqueueDownloads(
    DramaDetail detail,
    List<Episode> episodes, {
    int quality = 0,
  }) async {
    enqueued.add((
      drama: detail.drama.id,
      episodes: [for (final episode in episodes) episode.number],
      quality: quality,
    ));
    return episodes.length;
  }

  @override
  Future<void> controlDownloads(String command, {String id = ''}) async {
    if (failingControls.contains(id)) throw AppFailure('无法处理 $id');
    controls.add('$command|$id');
  }

  CatalogPage pageFor(String source, String category, String query, int page) =>
      CatalogPage([
        query.isEmpty
            ? drama('$category-$page', source: source, title: '分类$category')
            : drama('found', source: source, title: '搜到的剧'),
      ], page: page);

  @override
  Future<void> initialize() async {}

  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => categoryList;

  @override
  Future<CatalogPage> recommendations(
    String genre, {
    bool more = false,
    bool force = false,
  }) async {
    recommendRequests.add((more: more, force: force));
    return CatalogPage(recommended);
  }

  @override
  Future<List<RankingBoard>> rankingBoards() async => boardList;

  @override
  Future<RankingPage> rankings(
    String board, {
    int page = 1,
    bool force = false,
  }) async {
    rankingRequests.add('$board|$page${force ? '!' : ''}');
    return RankingPage(
      items: [
        for (var rank = page * 2 - 1; rank <= page * 2; rank++)
          RankingItem(rank, drama('$board-$rank', title: '$board第$rank名')),
      ],
      page: page,
      hasMore: page < 2,
    );
  }

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    catalogRequests.add('$source|$category|$query|$page${force ? '!' : ''}');
    if (failure.isNotEmpty) throw AppFailure(failure);
    return pageFor(source, category, query, page);
  }

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      cachedPages['$source|$category'] ?? CatalogPage(const []);

  @override
  Future<List<String>> suggestions(String query) async => suggestionList;

  @override
  Future<String> cover(Drama drama, {bool force = false}) async =>
      throw AppFailure('测试数据没有海报');

  final details = <String, DramaDetail>{};
  String detailFailure = '';
  int detailRequests = 0;

  @override
  Future<DramaDetail> detail(Drama drama) async {
    detailRequests++;
    if (detailFailure.isNotEmpty) throw AppFailure(detailFailure);
    return details[drama.id] ?? DramaDetail(drama, const []);
  }

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async => throw UnimplementedError();

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelPlayback() async {}

  @override
  Future<void> release(String session) async {}
}
