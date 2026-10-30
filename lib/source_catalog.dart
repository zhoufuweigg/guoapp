import 'core_bridge.dart';
import 'models.dart';
import 'ranking_models.dart';

String categoryName(String name) {
  final compact = name.trim().replaceAll(RegExp(r'\s+'), '');
  return switch (compact) {
    'AI成人短剧' || 'AI短剧' => 'AI 短剧',
    'AI成人漫剧' || 'AI漫剧' => 'AI 漫剧',
    'AI换脸' => 'AI 换脸',
    'AI魔改' => 'AI 魔改',
    'AI剧' => 'AI 剧',
    '' => '未分类',
    _ => name.trim(),
  };
}

class SourceCatalog {
  SourceCatalog(this.repository, this.source);
  final AppRepository repository;
  final SourceSite source;
  List<CatalogCategory> _remote = const [];
  List<RankingBoard> _boards = const [];
  final _library = <String, Drama>{};

  static const recommendGenre = 'find_drama';
  static const topicPrefix = 'tag:';

  bool get recommends => source.id == SourceSite.hongguo.id;

  List<RankingBoard> get boards => _boards;

  List<CatalogCategory> get categories {
    final names = <String>{};
    final remote = [
      for (final category in _remote)
        if (category.id.isNotEmpty && names.add(categoryName(category.name)))
          CatalogCategory(category.id, categoryName(category.name)),
    ];
    final topics = remote.any(
      (category) => category.id.startsWith(topicPrefix),
    );
    final local = topics
        ? const <String>[]
        : ({
            for (final drama in _library.values) categoryName(drama.category),
          }.where(names.add).toList()..sort());
    return [
      CatalogCategory.all,
      ...remote,
      for (final name in local)
        CatalogCategory('local:$name', name, local: true),
    ];
  }

  Future<void> loadCategories({bool force = false}) async {
    try {
      remember((await repository.cached(source.id)).items);
    } catch (_) {}
    try {
      _boards = [
        for (final board in await repository.rankingBoards())
          if (board.source == source.id) board,
      ];
    } catch (_) {}
    _remote = await repository.categories(source.id, force: force);
  }

  Future<RankingPage> ranking(
    RankingBoard board, {
    int page = 1,
    bool force = false,
  }) => repository.rankings(board.id, page: page, force: force);

  void remember(Iterable<Drama> items) {
    for (final drama in items) {
      if (drama.source != source.id) continue;
      _library[drama.id] = _library[drama.id]?.merge(drama) ?? drama;
    }
  }

  Future<CatalogPage> cached(CatalogCategory category) async => _within(
    category,
    await repository.cached(source.id, category: _request(category)),
  );

  Future<CatalogPage> fetch(
    CatalogCategory category, {
    int page = 1,
    bool force = false,
  }) async {
    final result = await repository.catalog(
      source.id,
      category: _request(category),
      page: page,
      force: force,
    );
    return _within(category, result);
  }

  Future<CatalogPage> recommendations({
    bool more = false,
    bool force = false,
  }) => repository.recommendations(recommendGenre, more: more, force: force);

  Future<CatalogPage> search(String query, {int page = 1}) async {
    final result = await repository.catalog(
      source.id,
      query: query,
      page: page,
    );
    return CatalogPage(
      result.items,
      hasMore: source.pagedSearch && result.hasMore,
      warning: result.warning,
      page: result.page,
      fresh: result.fresh,
    );
  }

  String _request(CatalogCategory category) =>
      category.local ? '' : category.id;

  CatalogPage _within(CatalogCategory category, CatalogPage page) {
    remember(page.items);
    if (!category.local) return page;
    return CatalogPage(
      [
        for (final drama in _library.values)
          if (categoryName(drama.category) == category.name) drama,
      ],
      hasMore: page.hasMore,
      warning: page.warning,
      page: page.page,
      fresh: page.fresh,
    );
  }
}
