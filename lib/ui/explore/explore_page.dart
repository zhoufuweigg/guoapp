import 'package:flutter/material.dart';

import '../../explore_feed.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../shell/app_shell.dart';
import '../detail/detail_page.dart';
import '../widgets/bar_button.dart';
import '../widgets/category_tabs.dart';
import '../widgets/choice_panel.dart';
import '../widgets/drama_grid.dart';
import '../widgets/page_header.dart';
import '../widgets/source_bar.dart';
import '../widgets/status_view.dart';
import 'explore_hero.dart';
import 'source_actions.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, required this.store});
  final LocalStore store;

  @override
  State<ExplorePage> createState() => ExplorePageState();
}

class ExplorePageState extends State<ExplorePage> {
  ExploreFeed? _explore;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _tabsKey = GlobalKey();
  String _shown = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _explore ??= ExploreFeed(AppScope.of(context).repository, widget.store);
  }

  @override
  void dispose() {
    _explore?.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _explore?.refresh();
  }

  void _open(Drama drama) => openPage<void>(
    context,
    (_) => DetailPage(store: widget.store, drama: drama),
  );

  Future<void> _pickCategory(BuildContext anchor) async {
    final explore = _explore!;
    final value = await showChoicePanel<String>(
      context: anchor,
      title: '全部分类',
      options: [for (final tab in explore.tabs) ChoiceOption(tab.id, tab.name)],
      selected: explore.tab.id,
      grid: ChoiceGrid.categories,
    );
    if (value != null) explore.select(value);
  }

  void _searchSubmitted(SourceSite source, String query) {
    if (query.trim().isEmpty) return;
    _search.clear();
    openSearch(context, widget.store, source, query: query);
  }

  void _resetScroll(ExploreFeed explore) {
    final shown = '${explore.source?.id}|${explore.tab.id}';
    if (shown == _shown) return;
    _shown = shown;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _explore!,
    builder: (context, _) {
      final explore = _explore!;
      final source = explore.source;
      final form = AppScope.formFactorOf(context);
      final television = form == FormFactor.television;
      final desktop = form == FormFactor.window;
      _resetScroll(explore);
      if (source == null) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (!television) const PageHeader(title: '发现'),
                const Expanded(
                  child: StatusView(
                    title: '暂无可用站源',
                    message: '请在站源管理中开启站源，或联系管理员开放权限。',
                    icon: Icons.public_off_rounded,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      final inset = switch (form) {
        FormFactor.phone => 16.0,
        FormFactor.pad || FormFactor.window => 24.0,
        FormFactor.television => televisionInset,
      };
      final tabs = Padding(
        padding: EdgeInsets.symmetric(
          horizontal: form == FormFactor.phone ? 0 : inset,
        ),
        child: CategoryTabs<String>(
          key: _tabsKey,
          options: [
            for (final tab in explore.tabs) ChoiceOption(tab.id, tab.name),
          ],
          selected: explore.tab.id,
          onSelected: explore.select,
          onShowAll: _pickCategory,
        ),
      );
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (!television)
                SourceBar(
                  source: source.name,
                  searchController: _search,
                  onSwitchSource: (anchor) => pickSource(anchor, widget.store),
                  onOpenSearch: () => openSearch(context, widget.store, source),
                  onSearchSubmitted: (query) => _searchSubmitted(source, query),
                  actions: [
                    if (desktop)
                      BarButton(
                        icon: Icons.refresh_rounded,
                        tooltip: '刷新',
                        onPressed: explore.refresh,
                      ),
                  ],
                ),
              if (!television || explore.feed!.items.isEmpty) tabs,
              Expanded(child: _content(explore, inset, television, tabs)),
            ],
          ),
        ),
      );
    },
  );

  Widget _content(
    ExploreFeed explore,
    double inset,
    bool television,
    Widget tabs,
  ) {
    final feed = explore.feed!;
    final hero = _hero(explore);
    final items = explore.items;
    if (feed.items.isEmpty) {
      if (feed.loading) return const StatusView.loading();
      if (feed.error.isNotEmpty) {
        return StatusView(
          title: '暂时无法加载',
          message: feed.error,
          icon: Icons.cloud_off_rounded,
          action: '重试',
          onAction: () => feed.reload(force: true),
        );
      }
      return StatusView(
        title: '这里还没有剧',
        message: '换一个分类看看',
        icon: Icons.inbox_outlined,
        action: '刷新',
        onAction: () => feed.reload(force: true),
      );
    }
    final phone = AppScope.formFactorOf(context) == FormFactor.phone;
    final desktop = AppScope.formFactorOf(context) == FormFactor.window;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scroll = CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (television)
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
                sliver: SliverToBoxAdapter(child: tabs),
              ),
            if (hero != null)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, phone ? 12 : 16, inset, 0),
                sliver: SliverToBoxAdapter(child: hero),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, desktop ? 20 : 16, inset, 0),
              sliver: DramaSliverGrid(
                width: constraints.maxWidth - inset * 2,
                items: items,
                rankOf: explore.rankOf,
                autofocus: television && hero == null,
                onOpen: _open,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                inset,
                8,
                inset,
                television ? 27 : 16,
              ),
              sliver: SliverToBoxAdapter(child: FeedFooter(feed: feed)),
            ),
          ],
        );
        return Stack(
          children: [
            AutoLoadMore(
              feed: feed,
              child: television
                  ? scroll
                  : RefreshIndicator(onRefresh: explore.refresh, child: scroll),
            ),
            if (feed.loading)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        );
      },
    );
  }

  Widget? _hero(ExploreFeed explore) {
    if (explore.resume case final entry?) {
      final drama = entry.drama;
      final total = drama.episodes;
      final next = entry.finished && entry.episode < total
          ? entry.episode + 1
          : entry.episode;
      return ExploreHero(
        drama: drama,
        kicker: '继续观看',
        meta: total > 0
            ? '看到第 ${entry.episode} 集 · 共 $total 集'
            : '看到第 ${entry.episode} 集',
        progress: total > 0 ? entry.episode / total : null,
        action: '继续第 $next 集',
        onPlay: () => _open(drama),
        onDetail: () => _open(drama),
      );
    }
    if (explore.featured case final drama?) {
      return ExploreHero(
        drama: drama,
        kicker: '今日推荐',
        meta: [
          if (drama.category.isNotEmpty) drama.category,
          if (drama.episodes > 0) '共 ${drama.episodes} 集',
        ].join(' · '),
        action: '立即观看',
        onPlay: () => _open(drama),
        onDetail: () => _open(drama),
      );
    }
    return null;
  }
}
