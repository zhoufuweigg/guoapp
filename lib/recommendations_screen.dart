import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_filters.dart';
import 'catalog_progress.dart';
import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_launch_screen.dart';
import 'widgets.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = false,
    this.progressKeyBase = 'hongguo:app:recommendations',
  });
  final AppRepository repository;
  final LocalStore store;
  final bool embedded;

  /// 浏览断点存储键前缀：最终键为 `$progressKeyBase:$二级分类`，
  /// 使真人剧 / 漫剧 / AI 剧各自独立记忆滚动位置。
  final String progressKeyBase;

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  static const _genres = [
    CatalogCategory('short_play', '真人剧'),
    CatalogCategory('comic_series', '漫剧'),
    CatalogCategory('ai_series', 'AI 剧'),
  ];
  final _scroll = ScrollController();
  String _genre = 'short_play';
  List<Drama> _items = [];
  bool _loading = false;
  bool _more = false;
  bool _hasMore = true;
  bool _failedMore = false;
  String? _error;
  int _generation = 0;

  /// 浏览断点：网格几何 + 防抖保存 + 待恢复断点
  double _gridRowExtent = 0;
  int _gridColumns = 1;
  double _lastPixels = 0;
  Timer? _progressSaveTimer;
  CatalogProgress? _pendingRestore;
  int _restoreWaits = 0;

  /// 当前二级分类的断点存储键（每个分类独立记忆）。
  String get _progressKey => '${widget.progressKeyBase}:$_genre';

  @override
  void initState() {
    super.initState();
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    _scroll.addListener(_onScroll);
    _scheduleRestore();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    unawaited(widget.repository.cancelRecommendations());
    // 离开推荐视图前把当前分类的断点落盘
    _flushProgress();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients) _lastPixels = _scroll.position.pixels;
    _scheduleProgressSave();
  }

  /// 滚动停止后保存当前分类的浏览断点（防抖，避免高频写盘）。
  void _scheduleProgressSave() {
    if (!widget.store.playbackPreferences.saveCatalogProgress) return;
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(
      const Duration(milliseconds: 400),
      _saveProgress,
    );
  }

  /// 立即落盘当前分类断点（切分类 /  dispose 等场景防止防抖未触发丢失）。
  void _flushProgress() {
    _progressSaveTimer?.cancel();
    _saveProgress();
  }

  void _saveProgress() {
    _progressSaveTimer = null;
    if (!widget.store.playbackPreferences.saveCatalogProgress) return;
    // 加载中 / 恢复定位过程中不回写断点
    if (_loading || _more || _pendingRestore != null) return;
    if (_gridRowExtent <= 0 || _items.isEmpty) return;
    final pixels = _lastPixels;
    if (pixels <= 0) return;
    final row = (pixels / _gridRowExtent).floor();
    final index = (row * _gridColumns).clamp(0, _items.length - 1);
    unawaited(
      widget.store.saveCatalogProgress(
        _progressKey,
        CatalogProgress.capture(
          ids: _items.map((drama) => drama.id).toList(),
          titles: _items.map((drama) => drama.title).toList(),
          index: index,
          now: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  /// 进入 / 切换二级分类时装载该分类自己的断点。
  void _scheduleRestore() {
    if (!widget.store.playbackPreferences.saveCatalogProgress) return;
    // 先清除旧分类的待恢复断点，避免在错误的分类里锚定
    _pendingRestore = null;
    final progress = widget.store.catalogProgress[_progressKey];
    if (progress == null) return;
    _pendingRestore = progress;
    _restoreWaits = 0;
  }

  void _tryRestore() {
    final progress = _pendingRestore;
    if (progress == null) return;
    if (_loading || _more) return;
    if (_gridRowExtent <= 0 || _items.isEmpty) {
      // 列表尚未挂载（首屏数据刚到），下一帧再试；上限 6 帧。
      // 超时仍未就绪说明推荐流处于错误 / 空态，放弃恢复并清除标记，
      // 否则卡住的 _pendingRestore 会让该分类永远无法保存新断点。
      if (_restoreWaits < 6) {
        _restoreWaits++;
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryRestore());
        return;
      }
      _pendingRestore = null;
      return;
    }
    final ids = _items.map((drama) => drama.id).toList();
    var index = ids.indexOf(progress.dramaId);
    var anchored = false;
    if (index < 0) {
      // 断点视频可能已下架：经相邻视频重新锚定到附近
      for (final neighbor in progress.neighbors) {
        final found = ids.indexOf(neighbor);
        if (found >= 0) {
          index = found;
          anchored = true;
          break;
        }
      }
    }
    if (index < 0) {
      // 本轮推荐是有限集合，找不到就放弃（刷新会开启新一轮）
      _pendingRestore = null;
      return;
    }
    // 断点行上方保留一行上下文；锚定恢复时断点就在视口顶部
    final row = (index ~/ _gridColumns) - (anchored ? 0 : 1);
    final offset = (row < 0 ? 0 : row) * _gridRowExtent;
    _pendingRestore = null;
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          anchored ? '已定位到上次浏览附近' : '已定位到上次浏览：${progress.dramaTitle}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _metadataChanged() {
    final drama = widget.repository.catalogUpdates.latest;
    if (!mounted || drama == null) return;
    setState(() {
      _items = [
        for (final item in _items)
          item.id == drama.id ? item.merge(drama) : item,
      ];
    });
  }

  Future<void> _load({bool more = false, bool force = false}) async {
    if (more && (_loading || _more || !_hasMore)) return;
    final generation = ++_generation;
    final genre = _genre;
    setState(() {
      _loading = !more;
      _more = more;
      _error = null;
      _failedMore = more;
    });
    try {
      await widget.repository.cancelRecommendations();
      if (!mounted || generation != _generation) return;
      final page = await widget.repository.recommendations(
        genre,
        more: more,
        force: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore;
        _error = page.warning.isEmpty ? null : page.warning;
        _loading = _more = false;
      });
      if (_pendingRestore != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryRestore());
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = _more = false;
        _error = error.toString();
      });
      // 与目录一致：失败且已有可见条目时放弃恢复，避免卡住后续保存
      if (more || _items.isNotEmpty) _pendingRestore = null;
    }
  }

  void _select(String genre) {
    if (_genre == genre) return;
    // 先落盘旧分类断点（网格即将卸载，防抖计时可能还没到）
    _flushProgress();
    setState(() {
      _genre = genre;
      _items = [];
      _hasMore = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _lastPixels = 0;
    _scheduleRestore();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final refresh = RefreshAction(
      loading: _loading || _more,
      tooltip: '刷新推荐',
      onPressed: () => _load(force: true),
    );
    final content = Column(
      children: [
        CatalogFilters(
          categories: _genres,
          category: _genre,
          onCategory: _select,
          onRetry: () => _load(force: true),
          trailing: widget.embedded ? refresh : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '公开推荐 · 已加载 ${_items.length} 部',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        if (_loading && _items.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        if (_error != null && _items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loading || _more
                      ? null
                      : () => _load(more: _failedMore, force: !_failedMore),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        Expanded(
          child: !widget.store.allowsSource('hongguo')
              ? const StatusPanel(title: '当前用户未开放红果', message: '可在用户管理中调整站源权限。')
              : _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? StatusPanel(
                  title: _error == null ? '暂无推荐' : '推荐暂时无法加载',
                  message: _error ?? '稍后刷新可获取新的推荐。',
                  onRetry: () => _load(force: true),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // 记录网格几何：浏览断点的滚动位置 ↔ item 索引换算
                    final gridDelegate = dramaGridDelegate(
                      context,
                      constraints.maxWidth - 32,
                    ) as SliverGridDelegateWithFixedCrossAxisCount;
                    final itemExtent = gridDelegate.mainAxisExtent;
                    _gridRowExtent = itemExtent == null
                        ? 0
                        : itemExtent + gridDelegate.mainAxisSpacing;
                    _gridColumns = gridDelegate.crossAxisCount;
                    return RefreshIndicator(
                      onRefresh: () => _load(force: true),
                      child: CustomScrollView(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverGrid(
                              gridDelegate: gridDelegate,
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final drama = _items[index];
                                return DramaTile(
                                  key: ValueKey(drama.id),
                                  drama: drama,
                                  repository: widget.repository,
                                  onTap: () => unawaited(
                                    openPlaybackDirectly(
                                      context,
                                      drama: drama,
                                      repository: widget.repository,
                                      store: widget.store,
                                    ),
                                  ),
                                );
                              }, childCount: _items.length),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              child: Center(
                                child: _more
                                    ? const CircularProgressIndicator()
                                    : _hasMore
                                    ? OutlinedButton.icon(
                                        onPressed: () => _load(more: true),
                                        icon: const Icon(
                                          Icons.auto_awesome_rounded,
                                        ),
                                        label: const Text('继续推荐'),
                                      )
                                    : TextButton(
                                        onPressed: () => _load(force: true),
                                        child: const Text('本轮推荐已看完，刷新获取新推荐'),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('红果推荐'), actions: [refresh]),
      body: SafeArea(top: false, child: content),
    );
  }
}
