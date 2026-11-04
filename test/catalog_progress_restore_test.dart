import 'package:duanju_app/catalog_progress.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 目录浏览断点的组件级回归：红果「全部」与二级分类各自独立保存/恢复。
class ProgressFixtureRepository extends AppRepository {
  ProgressFixtureRepository({this.itemsPerPage = 24, this.maxPage = 6});

  final int itemsPerPage;
  final int maxPage;
  final requests = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage(const []);

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    requests.add('$source|$category|$page');
    final prefix = category.isEmpty ? 'all' : category;
    return CatalogPage(
      [
        for (var i = 0; i < itemsPerPage; i++)
          Drama(
            id: '$source:$prefix-$page-$i',
            source: source,
            title: '$prefix 第$page页 剧集$i',
            episodes: 2,
            category: '合成数据',
          ),
      ],
      page: page,
      hasMore: page < maxPage,
    );
  }

  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => const [
    CatalogCategory('short_play', '真人剧'),
    CatalogCategory('comic_series', '漫剧'),
    CatalogCategory('ai_series', 'AI剧'),
  ];

  @override
  Future<DramaDetail> detail(Drama drama) async =>
      throw AppFailure('合成剧集没有详情');

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async => throw AppFailure('合成剧集不能播放');

  @override
  Future<void> cancelPlayback() async {}

  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async =>
      throw AppFailure('没有备用线路');

  @override
  Future<void> release(String session) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> create() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
  }

  Future<ProgressFixtureRepository> pumpHome(
    WidgetTester tester,
    LocalStore store,
  ) async {
    final repository = ProgressFixtureRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(repository: repository, store: store),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  /// 把目录网格向上拖 [dy]，再等过防抖保存计时（400ms）。
  Future<void> scrollCatalog(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(CustomScrollView).first, Offset(0, -dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('红果「全部」滚动后保存 hongguo: 断点', (tester) async {
    viewport(tester);
    final store = await create();
    await pumpHome(tester, store);
    expect(find.byType(CustomScrollView), findsWidgets);

    await scrollCatalog(tester, 900);

    final progress = store.catalogProgress['hongguo:'];
    expect(progress, isNotNull, reason: '「全部」目录应保存浏览断点');
    expect(progress!.dramaId, startsWith('hongguo:all-'));
  });

  testWidgets('红果二级分类各自保存独立断点', (tester) async {
    viewport(tester);
    final store = await create();
    await pumpHome(tester, store);

    // 切到「真人剧」并滚动
    await tester.tap(find.byKey(const ValueKey('category-category:真人剧')));
    await tester.pumpAndSettle();
    await scrollCatalog(tester, 600);
    final realPlay = store.catalogProgress['hongguo:category:真人剧'];
    expect(realPlay, isNotNull, reason: '真人剧分类应保存浏览断点');
    expect(realPlay!.dramaId, startsWith('hongguo:short_play-'));

    // 切回「全部」并滚动：两个键互不覆盖
    await tester.tap(find.byKey(const ValueKey('category-')));
    await tester.pumpAndSettle();
    await scrollCatalog(tester, 300);
    expect(store.catalogProgress['hongguo:category:真人剧'], isNotNull);
    final all = store.catalogProgress['hongguo:'];
    expect(all, isNotNull, reason: '「全部」目录应保存浏览断点');
    expect(all!.dramaId, startsWith('hongguo:all-'));
  });

  testWidgets('重新进入源后「全部」断点恢复定位', (tester) async {
    viewport(tester);
    final store = await create();
    await store.saveCatalogProgress(
      'hongguo:',
      CatalogProgress(
        dramaId: 'hongguo:all-2-20',
        dramaTitle: 'all 第2页 剧集20',
        neighbors: const ['hongguo:all-2-19', 'hongguo:all-2-21'],
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await pumpHome(tester, store);
    // 等恢复定位（首屏 + 续页到含断点的页面）
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('已定位到上次浏览：all 第2页 剧集20'), findsOneWidget);
  });
}
