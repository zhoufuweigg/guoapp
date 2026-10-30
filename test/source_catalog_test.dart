import 'package:duanju_app/models.dart';
import 'package:duanju_app/source_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _TopicRepository extends FakeRepository {
  @override
  CatalogPage pageFor(String source, String category, String query, int page) =>
      CatalogPage(
        [drama('p$page', source: source, category: '都市')],
        hasMore: true,
        page: page,
      );
}

void main() {
  test('categories normalize remote names and add cached topics', () async {
    final repository = FakeRepository()
      ..categoryList = const [
        CatalogCategory.all,
        CatalogCategory('short_play', '真人剧'),
        CatalogCategory('comic', 'AI成人漫剧'),
        CatalogCategory('comic_again', 'AI漫剧'),
      ]
      ..cachedPages['hongguo|'] = CatalogPage([
        drama('1', category: '都市'),
        drama('2', category: '成长'),
        drama('3', category: 'AI 漫剧'),
        drama('4', source: 'huangdou', category: '甜宠'),
      ]);
    final catalog = SourceCatalog(repository, SourceSite.hongguo);
    await catalog.loadCategories();
    expect(
      [for (final category in catalog.categories) category.id],
      ['', 'short_play', 'comic', 'local:成长', 'local:都市'],
    );
    expect(catalog.categories[2].name, 'AI 漫剧');
  });

  test('server topics replace the cached topics', () async {
    final repository = FakeRepository()
      ..categoryList = const [
        CatalogCategory.all,
        CatalogCategory('short_play', '真人剧'),
        CatalogCategory('tag:cate_96', '甜宠'),
        CatalogCategory('tag:cate_1', '都市'),
      ]
      ..cachedPages['hongguo|'] = CatalogPage([
        drama('1', category: '都市'),
        drama('2', category: '成长'),
      ]);
    final catalog = SourceCatalog(repository, SourceSite.hongguo);
    await catalog.loadCategories();
    expect(
      [for (final category in catalog.categories) category.id],
      ['', 'short_play', 'tag:cate_96', 'tag:cate_1'],
    );
  });

  test('a cached topic lists every remembered drama in it', () async {
    final repository = _TopicRepository()
      ..cachedPages['hongguo|'] = CatalogPage([
        drama('1', category: '都市'),
        drama('2', category: '成长'),
      ]);
    final catalog = SourceCatalog(repository, SourceSite.hongguo);
    await catalog.loadCategories();
    final topic = catalog.categories.last;
    expect(topic.local, isTrue);

    final page = await catalog.fetch(topic);
    expect(repository.catalogRequests, ['hongguo|||1']);
    expect(
      [for (final item in page.items) item.id],
      ['hongguo:1', 'hongguo:p1'],
    );
    expect(page.hasMore, isTrue);
  });

  test('search pages only where the source searches by page', () async {
    final repository = _TopicRepository();
    final huangdou = await SourceCatalog(
      repository,
      const SourceSite('huangdou', '黄豆', '精选短剧'),
    ).search('剧名');
    final hongguo = await SourceCatalog(
      repository,
      SourceSite.hongguo,
    ).search('剧名', page: 2);
    expect(huangdou.hasMore, isFalse);
    expect(hongguo.hasMore, isTrue);
    expect(repository.catalogRequests, ['huangdou||剧名|1', 'hongguo||剧名|2']);
  });
}
