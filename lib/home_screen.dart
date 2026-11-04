import 'dart:async';
import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'app_bottom_navigation.dart';
import 'app_glass.dart';
import 'catalog_progress.dart';
import 'core_bridge.dart';
import 'catalog_filters.dart';
import 'catalog_browser.dart';
import 'catalog_sort.dart';
import 'catalog_sort_sheet.dart';
import 'recommendations_screen.dart';
import 'rankings_screen.dart';
import 'detail_screen.dart';
import 'playback_launch_screen.dart';
import 'downloads_screen.dart';
import 'local_store.dart';
import 'lan_screen.dart';
import 'models.dart';
import 'remote_widgets.dart';
import 'widgets.dart';
import 'vip_icon.dart';
import 'settings_screen.dart';
import 'profiles_screen.dart';
import 'search_input.dart';
import 'sources_screen.dart';
import 'batch_download_screen.dart';
import 'batch_downloads.dart';
import 'drama_actions.dart';
import 'library_updater.dart';
import 'saved_library.dart';

/// 桌面端（鼠标）也允许拖拽切换页面。
///
/// Flutter 默认 [ScrollBehavior.dragDevices] 不含 [PointerDeviceKind.mouse]
/// （拖拽手势预留给文本选择），触屏 / 触控板不受影响；这里显式加入鼠标，
/// 使 Windows / Linux 桌面版的左右划切换与移动端一致。
class _PageSwipeBehavior extends ScrollBehavior {
  const _PageSwipeBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.mouse,
    PointerDeviceKind.unknown,
  };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.store});
  final AppRepository repository;
  final LocalStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _recommendationCategory = 'app:recommendations';

  /// 内容区 PageView 的稳定标识：确保导航切换 / 状态重建时复用同一
  /// [_PageViewState]，避免每次 rebuild 重建滚动位置（会导致滑动中点页面
  /// 跳回首屏）。
  final GlobalKey _pageViewKey = GlobalKey(debugLabel: 'home-content-pages');

  /// 页面被其他路由覆盖（如播放页压栈）时缓存的子树：
  /// 后台期间 store 的通知直接复用它，跳过整页网格重建。
  Widget? _backgroundCache;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  late SourceSite _source;
  bool _allSources = false;
  List<Drama> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _generation = 0;
  int _tab = 0;

  /// 底栏 / 侧栏 / Rail 中「设置」项的固定索引（与三点菜单的「下载」互换后，
  /// 原「下载」tab 槽位改为「设置」，与其他一级 tab 平级）。
  static const _settingsNavIndex = 3;

  /// 内容区 PageView 控制器（移动端）：点按底栏 tab 平滑滑动切换，左右划
  /// 内容区亦可切换（onPageChanged 同步底栏高亮）。
  late final PageController _pageController;
  String _submittedQuery = '';
  final _categorySelections = <String, String>{};
  late final CatalogBrowser _browser;
  bool _searchVisible = false;
  bool _categoriesLoading = false;
  String? _categoriesError;
  int _categoryGeneration = 0;
  late final LibraryUpdater _updater;
  final _changedSources = <String>{};
  final _selectedDramas = <String, Drama>{};
  Timer? _cacheRefreshTimer;
  bool _refreshingUpdatedCache = false;
  bool _selectionMode = false;
  bool _showRecommendations = false;
  String _sourceSignature = '';
  bool _catalogLoadScheduled = false;

  /// 目录网格几何：行高（item 高 + 行距）与列数，用于滚动位置 ↔ item 索引换算
  double _gridRowExtent = 0;
  int _gridColumns = 1;

  /// 最后一次滚动通知的位置：dispose / 控制器卸载后用兜底落盘断点
  double _lastCatalogPixels = 0;

  /// 待恢复的浏览断点（进入源时装载，定位成功后清除）
  CatalogProgress? _pendingRestore;
  int _restoreAttempts = 0;
  int _restoreWaits = 0;
  Timer? _progressSaveTimer;

  List<SourceGroup> get _sourceGroups {
    final groups = SourceGroup.fromSources(widget.store.sources);
    return [
      if (groups.length > 1) SourceGroup('all', '全部站源', widget.store.sources),
      ...groups,
    ];
  }

  SourceGroup get _group =>
      _sourceGroups
          .where((group) => group.id == (_allSources ? 'all' : _source.groupId))
          .firstOrNull ??
      SourceGroup(_source.groupId, _source.groupName, [_source]);
  bool get _onlineSearch => _group.sources.any((source) => source.onlineSearch);
  bool get _searchSuggestions =>
      _group.sources.any((source) => source.searchSuggestions);
  String get _searchHint {
    final online = _group.sources
        .where((source) => source.onlineSearch)
        .toList();
    if (online.isEmpty) {
      return '筛选本机已更新剧库';
    }
    final names = online.map((source) => source.name).join('、');
    return online.length == _group.sources.length
        ? '搜索$names'
        : '搜索$names及本机剧库';
  }

  String get _category => _categorySelections[_group.id] ?? '';
  List<CatalogCategory> get _categories => _browser.categories(_group);
  String get _displayCategory =>
      _showRecommendations ? _recommendationCategory : _category;
  List<CatalogCategory> get _displayCategories => [
    CatalogCategory.all,
    if (_group.id == 'hongguo')
      const CatalogCategory(_recommendationCategory, '推荐'),
    ..._categories.where((entry) => entry.id.isNotEmpty),
  ];

  /// 浏览断点的存储键：源分组 + 当前二级分类。
  ///
  /// 每个源、每个分类（含红果「推荐」视图）各自独立记忆滚动位置，
  /// 切换分类 / 站源后回到原分类仍能继续上次的浏览进度。
  String get _progressKey => '${_group.id}:$_displayCategory';

  Future<void> _loadCategories({
    bool force = false,
    bool cacheOnly = false,
  }) async {
    final generation = ++_categoryGeneration;
    final group = _group;
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    final error = await _browser.loadCategories(
      group,
      force: force,
      cacheOnly: cacheOnly,
    );
    if (!mounted ||
        generation != _categoryGeneration ||
        group.id != _group.id) {
      return;
    }
    setState(() {
      _categoriesLoading = false;
      _categoriesError = error;
    });
    if (!_showRecommendations &&
        _category.isNotEmpty &&
        !_categories.any((entry) => entry.id == _category)) {
      _changeCategory('');
    }
  }

  Future<void> _refreshCatalog() async {
    // 下拉刷新是用户主动回到顶部的行为，取消待恢复断点与待保存计时
    _pendingRestore = null;
    _progressSaveTimer?.cancel();
    if (widget.repository.supportsSourceManagement) {
      if (_group.sources.any((source) => _updater.busy(source.id))) return;
      _pauseCatalog();
      await _updater.update(_group.sources);
      return;
    }
    await _loadCategories(force: true);
    if (mounted) await _load(force: true);
  }

  void _updateChanged() {
    if (mounted) setState(() {});
  }

  /// 密码锁切换后可见站源会变，这里把当前站源归一化到仍然可见的站源。
  void _sourcesChanged() {
    if (!mounted) return;
    final visible = widget.store.sources;
    final signature = visible.map((site) => site.id).join(',');
    if (signature == _sourceSignature) return;
    final wasEmpty = _sourceSignature.isEmpty;
    _sourceSignature = signature;
    if (visible.isEmpty) {
      setState(() {
        _items = [];
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
      });
      return;
    }
    final allowed = visible.map((site) => site.id).toSet();
    if (!wasEmpty &&
        allowed.contains(_source.id) &&
        _source.id == widget.store.source) {
      return;
    }
    _changeSource(SourceSite.byId(widget.store.source));
  }

  void _catalogUpdated(String source) {
    if (!mounted) return;
    _changedSources.add(source);
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      unawaited(_reloadUpdatedCache());
    });
  }

  Future<void> _reloadUpdatedCache() async {
    if (_refreshingUpdatedCache) return;
    _refreshingUpdatedCache = true;
    final epoch = widget.store.profileEpoch;
    try {
      while (mounted &&
          _changedSources.isNotEmpty &&
          epoch == widget.store.profileEpoch) {
        final sources = Set.of(_changedSources);
        _changedSources.clear();
        final updates = <String, Drama>{};
        for (final source in sources) {
          if (!widget.store.allowsSource(source)) continue;
          try {
            final cached = await widget.repository.cached(source);
            for (final drama in cached.items) {
              if (widget.store.allowsSource(drama.source)) {
                updates[drama.id] = drama;
              }
            }
          } catch (error) {
            if (mounted && epoch == widget.store.profileEpoch) {
              setState(() => _error = '更新后读取缓存失败：$error');
            }
          }
        }
        if (!mounted || epoch != widget.store.profileEpoch) return;
        _browser.updateDramas(updates.values);
        setState(() {
          _items = [
            for (final item in _items)
              updates[item.id] == null ? item : item.merge(updates[item.id]!),
          ];
          for (final id in _selectedDramas.keys.toList()) {
            if (updates[id] != null) {
              _selectedDramas[id] = _selectedDramas[id]!.merge(updates[id]!);
            }
          }
        });
        await saveUserChange(
          context,
          () => widget.store.refreshDramas(updates.values),
        );
        if (!mounted || epoch != widget.store.profileEpoch) return;
        if (_group.sources.any((source) => sources.contains(source.id))) {
          await _loadCategories(cacheOnly: true);
          if (mounted &&
              !_loading &&
              !_loadingMore &&
              (!_onlineSearch || _search.text.trim().isEmpty)) {
            await _load(cacheOnly: true);
          }
        }
      }
    } finally {
      _refreshingUpdatedCache = false;
    }
  }

  void _changeGroup(SourceGroup group) {
    if (_group.id != group.id) {
      _changeSource(group.sources.first, allSources: group.id == 'all');
    }
  }

  void _changeCategory(String category) {
    if (category == _recommendationCategory && _group.id == 'hongguo') {
      if (_showRecommendations) return;
      // 离开目录网格前先把当前分类的断点落盘（防抖计时可能还没到）
      _flushProgress();
      _pauseCatalog();
      setState(() {
        _showRecommendations = true;
        _selectionMode = false;
        _selectedDramas.clear();
        _search.clear();
        _searchVisible = false;
        _submittedQuery = '';
      });
      return;
    }
    if (_category == category && !_showRecommendations) return;
    _debounce?.cancel();
    // 先把当前分类的断点落盘，再切换（jumpTo(0) 会触发监听但不记录位置）
    _flushProgress();
    setState(() {
      _showRecommendations = false;
      _selectionMode = false;
      _selectedDramas.clear();
      _categorySelections[_group.id] = category;
      if (_onlineSearch) {
        _search.clear();
        _submittedQuery = '';
      }
      _items = [];
      _hasMore = true;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // 每个分类独立记忆断点：切换后装载该分类自己的浏览进度
    _progressSaveTimer?.cancel();
    _scheduleCatalogProgressRestore();
    _load(useCache: true);
  }

  void _toggleSearch() {
    if (AppLayout.isTelevision(context)) {
      _televisionSearch();
      return;
    }
    if (_showRecommendations) _changeCategory('');
    final hadQuery = _search.text.isNotEmpty;
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) _search.clear();
    });
    if (!_searchVisible && hadQuery) _searchChanged('');
  }

  void _openRankings() {
    _pauseCatalog();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RankingsScreen(
          repository: widget.repository,
          store: widget.store,
          initialGroup: _group.id,
        ),
      ),
    );
  }

  Future<void> _manageSources() async {
    _pauseCatalog();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SourcesScreen(
          repository: widget.repository,
          store: widget.store,
          initialSource: _source.id,
        ),
      ),
    );
    if (!mounted) return;
    await _loadCategories();
    if (mounted && (!_onlineSearch || _submittedQuery.isEmpty)) {
      await _load(useCache: true);
    }
  }

  Future<void> _chooseDisplayMode() async {
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('界面模式'),
        children: [
          RadioGroup<String>(
            groupValue: widget.store.displayMode,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in const {
                  'auto': '自动识别设备',
                  'television': '电视 / 遥控器',
                  'standard': '手机 / 电脑',
                }.entries)
                  RadioListTile<String>(
                    value: mode.key,
                    autofocus: mode.key == widget.store.displayMode,
                    title: Text(mode.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selection != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setDisplayMode(selection),
      );
    }
  }

  Future<void> _televisionSearch() async {
    final query = await showDialog<String>(
      context: context,
      builder: (_) => TelevisionSearchDialog(
        initialValue: _search.text,
        title: _group.id == 'all'
            ? '搜索已开放站源'
            : _onlineSearch
            ? '搜索${_group.name}短剧'
            : '筛选当前已加载短剧',
        recentSearches: widget.store.recentSearches,
        onCancel: () => unawaited(widget.repository.cancelSuggestions()),
        suggestions: _searchSuggestions ? widget.repository.suggestions : null,
      ),
    );
    if (query != null && mounted) {
      _submitSearch(query);
    }
  }

  void _televisionBack() {
    if (_selectionMode) {
      _cancelSelection();
    } else if (_tab != 0) {
      _changeTab(0);
      _animateToTab(0);
    } else if (_search.text.isNotEmpty) {
      _search.clear();
      _searchChanged('');
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _tab);
    _scroll.addListener(_onCatalogScroll);
    _source = SourceSite.byId(widget.store.source);
    _allSources = widget.store.catalogView.allSources;
    _sourceSignature = widget.store.sources.map((site) => site.id).join(',');
    _browser = CatalogBrowser(widget.repository);
    _updater = LibraryUpdater(
      widget.repository,
      widget.store,
      onCatalogChanged: _catalogUpdated,
    )..addListener(_updateChanged);
    _updater.startWatching();
    widget.store.addListener(_sourcesChanged);
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    if (widget.store.sources.isNotEmpty) {
      _load(useCache: true);
      _loadCategories();
      _scheduleCatalogProgressRestore();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _updater.removeListener(_updateChanged);
    _updater.dispose();
    _cacheRefreshTimer?.cancel();
    widget.store.removeListener(_sourcesChanged);
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    _generation++;
    _categoryGeneration++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    _debounce?.cancel();
    _progressSaveTimer?.cancel();
    _flushProgress();
    _search.dispose();
    _scroll.removeListener(_onCatalogScroll);
    _scroll.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onCatalogScroll() {
    if (_scroll.hasClients) _lastCatalogPixels = _scroll.position.pixels;
    // 断点保存独立于「加载更多」的早退条件：全部加载完毕后滚动同样要保存
    _scheduleProgressSave();
    if (!mounted ||
        _showRecommendations ||
        !_hasMore ||
        _loading ||
        _loadingMore ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final threshold = (position.viewportDimension * 1.5).clamp(320.0, 900.0);
    if (position.extentAfter > threshold || _catalogLoadScheduled) return;
    _catalogLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _catalogLoadScheduled = false;
      if (!mounted ||
          _showRecommendations ||
          !_hasMore ||
          _loading ||
          _loadingMore ||
          !_scroll.hasClients) {
        return;
      }
      unawaited(_load(more: true));
    });
  }

  /// 滚动停止后保存当前分类的浏览断点（防抖，避免高频写盘）。
  void _scheduleProgressSave() {
    if (!widget.store.playbackPreferences.saveCatalogProgress) return;
    // 搜索结果不是稳定目录，不记录断点
    if (_search.text.trim().isNotEmpty) return;
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(
      const Duration(milliseconds: 400),
      _saveCatalogProgress,
    );
  }

  /// 立即落盘当前分类断点（切分类 / 切源等场景先调用，防止防抖未触发丢失）。
  void _flushProgress() {
    _progressSaveTimer?.cancel();
    _saveCatalogProgress();
  }

  void _saveCatalogProgress() {
    _progressSaveTimer = null;
    if (!widget.store.playbackPreferences.saveCatalogProgress) return;
    // 搜索结果不是稳定目录，不记录断点
    if (_search.text.trim().isNotEmpty) return;
    // 推荐视图（红果）由 RecommendationsScreen 自行按二级分类管理，
    // 这里回写会把过期的目录网格状态写进推荐断点键
    if (_showRecommendations) return;
    // 恢复定位过程中的 jumpTo 不应回写断点
    if (_pendingRestore != null || _loading) return;
    if (_gridRowExtent <= 0) return;
    final items = _visible;
    if (items.isEmpty) return;
    // 用最后一次滚动通知的位置：dispose 等场景下控制器可能已无客户端
    final pixels = _lastCatalogPixels;
    if (pixels <= 0) return;
    final row = (pixels / _gridRowExtent).floor();
    final index = (row * _gridColumns).clamp(0, items.length - 1);
    unawaited(
      widget.store.saveCatalogProgress(
        _progressKey,
        CatalogProgress.capture(
          ids: items.map((drama) => drama.id).toList(),
          titles: items.map((drama) => drama.title).toList(),
          index: index,
          now: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  /// 进入源 / 切换分类时装载对应断点，待目录数据就绪后定位。
  void _scheduleCatalogProgressRestore() {
    if (!widget.store.playbackPreferences.saveCatalogProgress) return;
    // 推荐视图（红果）由 RecommendationsScreen 自行按二级分类管理
    if (_showRecommendations) return;
    if (_search.text.trim().isNotEmpty) return;
    // 先清除旧语境的待恢复断点，避免在错误的分类里锚定
    _pendingRestore = null;
    final progress = widget.store.catalogProgress[_progressKey];
    if (progress == null) return;
    _pendingRestore = progress;
    _restoreAttempts = 0;
    _restoreWaits = 0;
    _tryRestoreCatalogProgress();
  }

  void _tryRestoreCatalogProgress() {
    final progress = _pendingRestore;
    if (progress == null || !mounted) return;
    if (_loading || _loadingMore) return;
    if (!_scroll.hasClients || _gridRowExtent <= 0) {
      // 列表尚未挂载（首屏数据刚到），下一帧再试；上限 6 帧。
      // 超时未挂载说明目录处于错误 / 空态，放弃恢复并清除待恢复标记，
      // 否则卡住的 _pendingRestore 会让该分类永远无法保存新断点。
      if (_restoreWaits < 6) {
        _restoreWaits++;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _tryRestoreCatalogProgress(),
        );
        return;
      }
      _pendingRestore = null;
      return;
    }
    final items = _visible;
    if (items.isEmpty) {
      // 网格已挂载但可见条目为空（如全部被权限过滤）：无可恢复目标
      _pendingRestore = null;
      return;
    }
    final ids = items.map((drama) => drama.id).toList();
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
    if (index >= 0) {
      // 断点行上方保留一行上下文；锚定恢复时断点就在视口顶部
      final row = (index ~/ _gridColumns) - (anchored ? 0 : 1);
      final offset = (row < 0 ? 0 : row) * _gridRowExtent;
      _pendingRestore = null;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            anchored ? '已定位到上次浏览附近' : '已定位到上次浏览：${progress.dramaTitle}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    // 断点可能在尚未加载的后续页：继续加载（限次，避免无底洞）
    if (_hasMore && _restoreAttempts < 6) {
      _restoreAttempts++;
      unawaited(_load(more: true));
      return;
    }
    _pendingRestore = null;
  }

  void _metadataChanged() {
    final drama = widget.repository.catalogUpdates.latest;
    if (!mounted || drama == null || !widget.store.allowsSource(drama.source)) {
      return;
    }
    _browser.updateDrama(drama);
    setState(() {
      _items = [
        for (final item in _items)
          item.id == drama.id ? item.merge(drama) : item,
      ];
    });
    unawaited(saveUserChange(context, () => widget.store.refreshDrama(drama)));
  }

  Future<void> _load({
    bool more = false,
    bool useCache = false,
    bool force = false,
    bool cacheOnly = false,
  }) async {
    if (_showRecommendations) return;
    if (more && (_loading || _loadingMore || !_hasMore)) return;
    final generation = ++_generation;
    final group = _group;
    final query = _onlineSearch ? _search.text.trim() : '';
    setState(() {
      _error = null;
      if (query.isNotEmpty) _categorySelections[group.id] = '';
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
        if (query != _submittedQuery) _items = [];
      }
    });
    void accept(CatalogPage result, {bool cached = false}) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = result.items;
        _hasMore = result.hasMore;
        _submittedQuery = query;
        _loading = cached && !result.fresh;
        _loadingMore = false;
        _error = result.warning.isEmpty ? null : result.warning;
      });
      unawaited(
        saveUserChange(context, () => widget.store.refreshDramas(result.items)),
      );
      if (_pendingRestore != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _tryRestoreCatalogProgress(),
        );
      }
    }

    try {
      final result = await _browser.load(
        group,
        category: _category,
        query: query,
        more: more,
        useCache: useCache,
        force: force,
        cacheOnly: cacheOnly,
        onCached: (result) => accept(result, cached: true),
      );
      accept(result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
      // 加载失败：若已有可见条目（或续页失败），放弃本次恢复，
      // 避免卡住的 _pendingRestore 阻断用户滚动时的新断点保存；
      // 初始加载即失败时保留标记，用户重试成功后仍能恢复定位。
      if (more || _items.isNotEmpty) _pendingRestore = null;
    }
  }

  void _changeSource(SourceSite source, {bool allSources = false}) {
    if (_source.id == source.id && _allSources == allSources) {
      return;
    }
    // 切源前落盘当前「源+分类」的断点
    _flushProgress();
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _showRecommendations = false;
      _selectionMode = false;
      _selectedDramas.clear();
      _source = source;
      _allSources = allSources;
      _items = [];
      _hasMore = true;
      _submittedQuery = '';
      _error = null;
    });
    unawaited(
      saveUserChange(
        context,
        () => widget.store.setCatalogSource(source.id, allSources: allSources),
      ),
    );
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    _load(useCache: true);
    _loadCategories();
    _scheduleCatalogProgressRestore();
  }

  void _searchChanged(String query) {
    _debounce?.cancel();
    _selectionMode = false;
    _selectedDramas.clear();
    if (_onlineSearch && (_loading || _loadingMore)) {
      _generation++;
      unawaited(_browser.cancel());
      _loading = _loadingMore = false;
    }
    setState(() {});
    if (_onlineSearch && query.trim().isEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), () => _load());
    }
  }

  void _submitSearch(String query) {
    if (_showRecommendations) {
      _showRecommendations = false;
      _categorySelections[_group.id] = '';
    }
    _selectionMode = false;
    _selectedDramas.clear();
    _search.text = query.trim();
    _debounce?.cancel();
    if (_search.text.isNotEmpty) {
      unawaited(
        saveUserChange(
          context,
          () => widget.store.rememberSearch(_search.text),
        ),
      );
    }
    if (_onlineSearch) {
      _load();
    } else {
      setState(() {});
    }
  }

  Future<void> _chooseCatalogView() async {
    final selected = await chooseCatalogView(context, widget.store.catalogView);
    if (selected != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setCatalogView(selected),
      );
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _openDrama(Drama drama, {bool resume = false, bool download = false}) {
    _pauseCatalog();
    if (download) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailScreen(
            drama: drama,
            repository: widget.repository,
            store: widget.store,
            downloadOnOpen: true,
          ),
        ),
      );
      return;
    }
    unawaited(
      openPlaybackDirectly(
        context,
        drama: drama,
        repository: widget.repository,
        store: widget.store,
      ),
    );
  }

  void _changeTab(int tab) => setState(() {
    _tab = tab;
    _selectionMode = false;
    _selectedDramas.clear();
  });

  /// 连点「最近观看」6 次弹出站源密码锁（用于启用 / 关闭密码功能）。
  /// 仅多源包（真果鉴）生效；红果鉴单源包无密码功能。
  ///
  /// 「设置」与其他一级 tab 平级：点按直接切入设置 tab 内容区（有底栏、
  /// 无返回按钮）。移动端内容区为 PageView，点按 tab 时平滑滑动过去；
  /// 桌面 / 电视端为侧栏 / Rail 直接切换，无滑动。
  void _onNavSelected(int tab) {
    _changeTab(tab);
    _animateToTab(tab);
  }

  /// 移动端把内容区 PageView 平滑滑动到 [tab]（类浏览图片的左右滑动体验，
  /// 与底栏高亮同步）；桌面 / 电视端无操作。
  void _animateToTab(int tab) {
    final mobile =
        !AppLayout.isTelevision(context) &&
        MediaQuery.sizeOf(context).width < 840;
    if (!mobile || !_pageController.hasClients) return;
    if (_pageController.page?.round() == tab) return;
    _pageController.animateToPage(
      tab,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 内容区左右划切换（PageView.onPageChanged）：底栏高亮跟随滑动。
  void _onPageChanged(int page) {
    if (page == _tab) return;
    _changeTab(page);
  }

  /// 按 tab 索引构建内容页（PageView 每页固定 key，滑出后状态自然释放，
  /// 相邻页保持；_tab 变化不重建页面，避免滑动中途内容跳变）。
  Widget _tabPage(int tab, {required bool selectionInBody}) {
    switch (tab) {
      case 0:
        return widget.store.sources.isEmpty
            ? const StatusPanel(title: '暂无可用站源', message: '请联系管理员为当前用户开放站源。')
            : _catalog(selectionInBody: selectionInBody);
      case _settingsNavIndex:
        return SettingsScreen(
          key: const ValueKey('settings-tab'),
          repository: widget.repository,
          store: widget.store,
          embedded: true,
        );
      default:
        return SavedLibrary(
          key: ValueKey('saved-tab-$tab'),
          repository: widget.repository,
          store: widget.store,
          history: tab == 2,
          onOpen: _openDrama,
          onContinue: (drama) => _openDrama(drama, resume: true),
          onDownload:
              widget.repository.supportsDownloads && widget.store.canDownload
              ? (drama) => _openDrama(drama, download: true)
              : null,
        );
    }
  }

  void _cancelSelection() => setState(() {
    _selectionMode = false;
    _selectedDramas.clear();
  });

  void _selectDrama(Drama drama) {
    if (!widget.store.canDownload ||
        !widget.repository.supportsDownloads ||
        !widget.store.allowsSource(drama.source)) {
      return;
    }
    if (!_selectedDramas.containsKey(drama.id) &&
        _selectedDramas.length >= BatchDownloads.maxDramas) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('一次最多选择 50 部短剧，请分批下载')));
      return;
    }
    setState(() {
      _selectionMode = true;
      if (_selectedDramas.remove(drama.id) == null) {
        _selectedDramas[drama.id] = drama;
      }
    });
  }

  void _downloadSelected() {
    if (!widget.store.canDownload || _selectedDramas.isEmpty) return;
    _pauseCatalog();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BatchDownloadScreen(
          repository: widget.repository,
          store: widget.store,
          dramas: _selectedDramas.values.toList(),
        ),
      ),
    );
  }

  void _dramaActions(Drama drama) => showDramaActions(
    context,
    drama: drama,
    store: widget.store,
    onContinue: () => _openDrama(drama, resume: true),
    onDownload: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _openDrama(drama, download: true)
        : null,
    onSelect: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _selectDrama(drama)
        : null,
  );

  Widget _catalogTile(
    Drama drama, {
    FocusNode? focusNode,
    VoidCallback? onFocus,
  }) {
    final following = widget.store.following(drama.id);
    final canSelect =
        widget.store.canDownload && widget.repository.supportsDownloads;
    return DramaTile(
      key: ValueKey(drama.id),
      drama: drama,
      repository: widget.repository,
      focusNode: focusNode,
      onFocus: onFocus,
      onTap: () => _selectionMode ? _selectDrama(drama) : _openDrama(drama),
      onLongPress: canSelect ? () => _selectDrama(drama) : null,
      onMore: () => _dramaActions(drama),
      actions: DramaActionButton(
        drama: drama,
        onPressed: () => _dramaActions(drama),
      ),
      selected: _selectionMode ? _selectedDramas.containsKey(drama.id) : null,
      badge: following == null
          ? null
          : '${following.status.label}${following.hasUpdates ? ' · ${following.updateLabel}' : ''}',
    );
  }

  void _pauseCatalog() {
    _debounce?.cancel();
    _generation++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    setState(() {
      _loading = false;
      _loadingMore = false;
    });
  }

  bool get _supportsVipFilter =>
      _group.sources.any((source) => source.id == 'huangdou');
  bool get _hideVip => _supportsVipFilter && widget.store.hideVip;

  /// 顶栏玻璃层：液态玻璃（透镜折射）优先，否则纯模糊，再否则不绘制。
  Widget _buildTopBarGlass(
    BuildContext context, {
    required bool liquidGlass,
    required bool blurred,
  }) {
    final colors = Theme.of(context).colorScheme;
    if (liquidGlass) {
      if (LiquidGlassShaders.available) {
        return LiquidGlassPanel(
          style: LiquidGlassStyle.top,
          tint: colors.surface.withValues(alpha: 0.45),
          bottomBorderColor: colors.outlineVariant.withValues(alpha: 0.4),
        );
      }
      // 着色器不可用：退化为纯模糊外观（与液态玻璃关闭时一致）。
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: ColoredBox(color: colors.surface.withValues(alpha: 0.72)),
        ),
      );
    }
    if (!blurred) return const SizedBox.shrink();
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: ColoredBox(color: colors.surface.withValues(alpha: 0.72)),
      ),
    );
  }

  List<Drama> get _visible {
    final query = _search.text.trim().toLowerCase();
    return sortCatalog(
      _items.where((drama) {
        if (!widget.store.allowsSource(drama.source)) return false;
        if (_category.startsWith('local:') &&
            categoryName(drama.category) != _category.substring(6)) {
          return false;
        }
        if (_hideVip && drama.source == 'huangdou' && drama.vip) {
          return false;
        }
        return _onlineSearch ||
            query.isEmpty ||
            matchesDramaQuery(drama, query);
      }),
      widget.store.catalogView,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent && _backgroundCache != null) {
        return _backgroundCache!;
      }
      final child = LayoutBuilder(
        builder: (context, constraints) {
          final television = AppLayout.isTelevision(context);
          final desktop = constraints.maxWidth >= 840;
          final appearance = widget.store.themeAppearance;
          final platformBars = !desktop && !television;
          final blurredBars = appearance.blurBars && platformBars;
          final floatingBar = appearance.floatingBar && platformBars;
          // 液态玻璃顶栏：透镜折射替代纯模糊（需要内容延伸到顶栏之下）。
          final topLiquidGlass = appearance.liquidGlass && platformBars;
          final scaffold = Scaffold(
            extendBodyBehindAppBar: blurredBars || topLiquidGlass,
            extendBody: floatingBar || blurredBars,
            appBar: AppBar(
              backgroundColor: blurredBars || topLiquidGlass
                  ? Colors.transparent
                  : null,
              elevation: blurredBars || topLiquidGlass ? 0 : null,
              scrolledUnderElevation: blurredBars || topLiquidGlass ? 0 : null,
              flexibleSpace: blurredBars || topLiquidGlass
                  ? ValueListenableBuilder<int>(
                      // 着色器异步就绪后重建，从纯模糊切换到液态玻璃。
                      valueListenable: LiquidGlassShaders.ready,
                      builder: (context, _, _) => _buildTopBarGlass(
                        context,
                        liquidGlass: topLiquidGlass,
                        blurred: blurredBars,
                      ),
                    )
                  : null,
              toolbarHeight: television ? 64 : null,
              titleSpacing: 12,
              title: _selectionMode
                  ? const Text(
                      '选择短剧',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : _tab == 0
                  ? PopupMenuButton<SourceGroup>(
                      key: const ValueKey('source-switch'),
                      tooltip: '切换站源',
                      enabled: _sourceGroups.length > 1,
                      onSelected: _changeGroup,
                      itemBuilder: (_) => [
                        for (final group in _sourceGroups)
                          PopupMenuItem(
                            value: group,
                            child: Row(
                              children: [
                                Expanded(child: Text(group.name)),
                                if (group.id == _group.id)
                                  const Icon(Icons.check_rounded, size: 20),
                              ],
                            ),
                          ),
                      ],
                      child: SizedBox(
                        height: 48,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _group.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (_sourceGroups.length > 1)
                              const Icon(Icons.expand_more_rounded),
                          ],
                        ),
                      ),
                    )
                  : _tab == _settingsNavIndex
                  ? const Text('设置')
                  : const Text(appName),
              actions: [
                if (_selectionMode) ...[
                  TextButton(
                    key: const ValueKey('clear-catalog-selection'),
                    onPressed: _selectedDramas.isEmpty
                        ? null
                        : () => setState(_selectedDramas.clear),
                    child: const Text('清空'),
                  ),
                  TextButton(
                    key: const ValueKey('cancel-catalog-selection'),
                    onPressed: _cancelSelection,
                    child: const Text('取消'),
                  ),
                ] else ...[
                  if (_tab == 1)
                    IconButton(
                      key: const ValueKey('follow-lan-sync'),
                      tooltip: '追剧同步',
                      onPressed: () => openLanSync(context),
                      icon: const Icon(Icons.sync_rounded),
                    ),
                  if (_tab == 0) ...[
                    if (!_showRecommendations)
                      IconButton(
                        tooltip:
                            '排序与筛选 · ${widget.store.catalogView.sort.label}',
                        onPressed: _chooseCatalogView,
                        color:
                            widget.store.catalogView.sort !=
                                    CatalogSort.source ||
                                widget.store.catalogView.release.isNotEmpty
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        icon: const Icon(Icons.sort_rounded),
                      ),
                    IconButton(
                      key: const ValueKey('open-rankings'),
                      tooltip: '榜单',
                      onPressed: widget.store.sources.isEmpty
                          ? null
                          : _openRankings,
                      icon: const Icon(Icons.leaderboard_outlined),
                    ),
                    if (!_showRecommendations &&
                        widget.store.canDownload &&
                        widget.repository.supportsDownloads)
                      IconButton(
                        key: const ValueKey('select-catalog-dramas'),
                        tooltip: '多选下载',
                        onPressed: () => setState(() => _selectionMode = true),
                        icon: const Icon(Icons.checklist_rounded),
                      ),
                    IconButton(
                      key: const ValueKey('toggle-search'),
                      tooltip: _searchVisible ? '收起搜索' : '搜索',
                      icon: Icon(
                        _searchVisible
                            ? Icons.search_off_rounded
                            : Icons.search_rounded,
                      ),
                      onPressed: _toggleSearch,
                    ),
                  ],
                  if (_tab == 0 &&
                      !_showRecommendations &&
                      constraints.maxWidth >= 400)
                    RefreshAction(
                      key: const ValueKey('catalog-refresh'),
                      loading:
                          _loading ||
                          _loadingMore ||
                          _categoriesLoading ||
                          _group.sources.any(
                            (source) => _updater.busy(source.id),
                          ),
                      tooltip: '更新剧库',
                      onPressed: widget.store.sources.isEmpty
                          ? null
                          : _refreshCatalog,
                    ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    onSelected: (value) {
                      if (value == 'update') {
                        _refreshCatalog();
                      } else if (value == 'sources') {
                        _manageSources();
                      } else if (value == 'downloads') {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DownloadsScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        );
                      } else if (value == 'users') {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ProfilesScreen(store: widget.store),
                          ),
                        );
                      } else if (value == 'display') {
                        _chooseDisplayMode();
                      } else if (value == 'about') {
                        showAboutDialog(
                          context: context,
                          applicationName: appName,
                          applicationVersion: AppLayout.versionOf(context),
                          applicationIcon: const Icon(
                            Icons.play_circle_filled_rounded,
                            size: 48,
                            color: Color(0xFFFF765F),
                          ),
                          children: [
                            const Text('独立运行，打开即可浏览和播放。观看记录与追剧收藏保存在当前设备。'),
                          ],
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      if (_tab == 0 &&
                          !_showRecommendations &&
                          constraints.maxWidth < 400)
                        PopupMenuItem(
                          value: 'update',
                          enabled:
                              widget.store.sources.isNotEmpty &&
                              !_group.sources.any(
                                (source) => _updater.busy(source.id),
                              ),
                          child: const Text('更新剧库'),
                        ),
                      if (widget.repository.supportsSourceManagement)
                        const PopupMenuItem(
                          value: 'sources',
                          child: Text('站源管理'),
                        ),
                      const PopupMenuItem(value: 'users', child: Text('用户管理')),
                      if (widget.store.canDownload)
                        const PopupMenuItem(
                          value: 'downloads',
                          child: Text('下载'),
                        ),
                      const PopupMenuItem(
                        value: 'display',
                        child: Text('界面模式'),
                      ),
                      const PopupMenuItem(
                        value: 'about',
                        child: Text('关于$appName'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(width: 8),
              ],
            ),
            body: Padding(
              padding: EdgeInsets.only(
                top: blurredBars
                    ? MediaQuery.paddingOf(context).top +
                          (television ? 64 : kToolbarHeight)
                    : 0,
              ),
              // 底部不裁切：让列表内容从悬浮底栏下方穿过，模糊/液态玻璃才有内容可糊；
              // 列表尾部通过 MediaQuery.padding.bottom（extendBody 时 = 底栏高度）补偿。
              child: SafeArea(
                top: !blurredBars,
                bottom: false,
                child: Row(
                  children: [
                    if (television) ...[
                      SizedBox(
                        width: 164,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 24, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in [
                                (Icons.explore_rounded, '发现'),
                                (Icons.bookmark_rounded, '追剧'),
                                (Icons.history_rounded, '最近观看'),
                                (Icons.settings_rounded, '设置'),
                              ].indexed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: RemoteButton(
                                    key: ValueKey('tv-nav-${entry.$1}'),
                                    label: entry.$2.$2,
                                    icon: entry.$2.$1,
                                    selected: _tab == entry.$1,
                                    autofocus: entry.$1 == 0,
                                    onPressed: () => _onNavSelected(entry.$1),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                    ] else if (desktop) ...[
                      NavigationRail(
                        selectedIndex: _tab,
                        onDestinationSelected: _onNavSelected,
                        labelType: NavigationRailLabelType.all,
                        groupAlignment: -.8,
                        destinations: [
                          NavigationRailDestination(
                            icon: Icon(Icons.explore_outlined),
                            selectedIcon: Icon(Icons.explore),
                            label: Text('发现'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.bookmark_border_rounded),
                            selectedIcon: Icon(Icons.bookmark_rounded),
                            label: Text('追剧'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.history_rounded),
                            label: Text('最近观看'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings_rounded),
                            label: Text('设置'),
                          ),
                        ],
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                    ],
                    Expanded(
                      child: desktop || television
                          ? _tabPage(_tab, selectionInBody: true)
                          : ScrollConfiguration(
                              behavior: const _PageSwipeBehavior(),
                              child: PageView.builder(
                                key: _pageViewKey,
                                controller: _pageController,
                                onPageChanged: _onPageChanged,
                                itemCount: 4,
                                itemBuilder: (context, index) =>
                                    _tabPage(index, selectionInBody: false),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: desktop || television
                ? null
                : _selectionMode
                ? _selectionBar()
                : AppBottomNavigation(
                    selectedIndex: _tab,
                    onDestinationSelected: _onNavSelected,
                    floating: floatingBar,
                    blurred: blurredBars,
                    liquidGlass: floatingBar && appearance.liquidGlass,
                    destinations: [
                      NavigationDestination(
                        icon: Icon(Icons.explore_outlined),
                        selectedIcon: Icon(Icons.explore),
                        label: '发现',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bookmark_border_rounded),
                        selectedIcon: Icon(Icons.bookmark_rounded),
                        label: '追剧',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.history_rounded),
                        label: '最近观看',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: '设置',
                      ),
                    ],
                  ),
          );
          if (!television && !_selectionMode && _tab == 0) return scaffold;
          return PopScope(
            // 「设置」等非首 tab 为一级页面：系统返回先平滑滑回首个 tab，而不是
            // 直接退出应用；首 tab 的返回保持原有退出行为。
            canPop:
                _tab == 0 &&
                !_selectionMode &&
                (!television || _search.text.isEmpty),
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _televisionBack();
            },
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(context).maybePop(),
                const SingleActivator(LogicalKeyboardKey.goBack): () =>
                    Navigator.of(context).maybePop(),
              },
              child: scaffold,
            ),
          );
        },
      );
      _backgroundCache = child;
      return child;
    },
  );

  Widget _catalog({required bool selectionInBody}) {
    final items = _visible;
    final television = AppLayout.isTelevision(context);
    return Column(
      children: [
        if (_searchVisible && !television)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SearchInput(
              key: ValueKey('search-${_group.id}'),
              controller: _search,
              autofocus: true,
              hint: _searchHint,
              suggestions: _searchSuggestions
                  ? widget.repository.suggestions
                  : null,
              onChanged: _searchChanged,
              onCancel: () => unawaited(widget.repository.cancelSuggestions()),
              onSearch: _submitSearch,
            ),
          ),
        if (_searchVisible &&
            _search.text.trim().isEmpty &&
            widget.store.recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final query in widget.store.recentSearches)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.history_rounded,
                                size: 16,
                              ),
                              label: Text(query),
                              onPressed: () => _submitSearch(query),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '清空最近搜索',
                  onPressed: () =>
                      saveUserChange(context, widget.store.clearRecentSearches),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
        CatalogFilters(
          key: ValueKey('filters-${_group.id}'),
          categories: _displayCategories,
          category: _displayCategory,
          error: _categoriesError,
          onCategory: _changeCategory,
          onRetry: () => _loadCategories(force: true),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_supportsVipFilter)
                IconButton(
                  tooltip: widget.store.hideVip ? 'VIP：隐藏' : 'VIP：显示',
                  onPressed: () => saveUserChange(
                    context,
                    () => widget.store.setHideVip(!widget.store.hideVip),
                  ),
                  icon: VipIcon(hidden: widget.store.hideVip),
                ),
            ],
          ),
        ),
        if (_showRecommendations)
          Expanded(
            child: RecommendationsScreen(
              repository: widget.repository,
              store: widget.store,
              embedded: true,
            ),
          )
        else ...[
          if (_loading && _items.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 18),
                        Text('正在加载剧集'),
                      ],
                    ),
                  )
                : _items.isEmpty && _error != null
                ? StatusPanel(
                    title: '暂时无法加载',
                    message: _error!,
                    onRetry: () => _load(force: true),
                    secondaryAction: widget.repository.supportsSourceManagement
                        ? TextButton(
                            onPressed: _manageSources,
                            child: const Text('站源诊断'),
                          )
                        : null,
                    icon: Icons.wifi_off_rounded,
                  )
                : items.isEmpty
                ? StatusPanel(
                    title: '没有找到匹配的短剧',
                    message: _hideVip
                        ? '可以换个搜索词，或显示 VIP 内容。'
                        : widget.store.sources.length > 1
                        ? '可以换个搜索词或切换站源。'
                        : '可以换个搜索词，或刷新后重试。',
                    onRetry:
                        _hasMore &&
                            !_loadingMore &&
                            (!_onlineSearch ||
                                _search.text.isEmpty ||
                                _group.sources.any(
                                  (source) => source.pagedSearch,
                                ))
                        ? () => _load(more: true)
                        : null,
                    action: '加载更多',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (television) {
                        return _televisionGrid(
                          items,
                          constraints.maxWidth,
                          key:
                              'catalog-${_group.id}-$_category-$_submittedQuery',
                          controller: _scroll,
                          footer: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                            child: Center(
                              child: _loadingMore
                                  ? const CircularProgressIndicator()
                                  : _hasMore
                                  ? RemoteButton(
                                      label: '加载更多',
                                      icon: Icons.expand_more,
                                      onPressed: () => _load(more: true),
                                    )
                                  : const Text('已经看到这里的全部剧集'),
                            ),
                          ),
                        );
                      }
                      final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
                      final gridDelegate = dramaGridDelegate(
                        context,
                        constraints.maxWidth - 2 * padding,
                      ) as SliverGridDelegateWithFixedCrossAxisCount;
                      // 记录网格几何：浏览断点的滚动位置 ↔ item 索引换算
                      final itemExtent = gridDelegate.mainAxisExtent;
                      _gridRowExtent = itemExtent == null
                          ? 0
                          : itemExtent + gridDelegate.mainAxisSpacing;
                      _gridColumns = gridDelegate.crossAxisCount;
                      return RefreshIndicator(
                        onRefresh: _refreshCatalog,
                        child: CustomScrollView(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                padding,
                                0,
                                padding,
                                16 + MediaQuery.paddingOf(context).bottom,
                              ),
                              sliver: SliverGrid(
                                gridDelegate: gridDelegate,
                                delegate: SliverChildBuilderDelegate(
                                  (_, index) => _catalogTile(items[index]),
                                  childCount: items.length,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      24 + MediaQuery.paddingOf(context).bottom,
                                ),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : _hasMore
                                      ? OutlinedButton.icon(
                                          onPressed: () => _load(more: true),
                                          icon: const Icon(
                                            Icons.expand_more_rounded,
                                          ),
                                          label: const Text('加载更多'),
                                        )
                                      : Text(
                                          '已经看到这里的全部剧集',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 12,
                                          ),
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
          if (_selectionMode && selectionInBody)
            _selectionBar(safeBottom: false),
        ],
      ],
    );
  }

  Widget _selectionBar({bool safeBottom = true}) {
    final theme = Theme.of(context);
    final count = _selectedDramas.length;
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: safeBottom,
          minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final summary = Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0 ? '点选要下载的短剧' : '已选 $count 部',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? '最多 ${BatchDownloads.maxDramas} 部'
                          : '下一步选择分集和画质',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
              final next = FilledButton(
                key: const ValueKey('download-selected-dramas'),
                onPressed: count == 0 ? null : _downloadSelected,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text('下一步'),
              );
              if (constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, const SizedBox(height: 12), next],
                );
              }
              return Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 16),
                  next,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _televisionGrid(
    List<Drama> items,
    double width, {
    required String key,
    ScrollController? controller,
    Widget? footer,
  }) {
    // 电视端使用 RemoteGrid（焦点滚动），不参与浏览断点的保存/恢复，
    // 显式清零网格几何，避免残留移动端换算值被误用。
    _gridRowExtent = 0;
    final columns = ((width - 36) / 150).floor().clamp(1, 8);
    final tileWidth = (width - 36 - (columns - 1) * 14) / columns;
    return RemoteGrid(
      key: ValueKey('tv-grid-$key'),
      itemKeys: items.map((item) => item.id).toList(),
      columns: columns,
      itemExtent: DramaTile.extentFor(context, tileWidth - 14) + 14,
      controller: controller,
      footer: footer,
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
      itemBuilder: (_, index, node, onFocus) =>
          _catalogTile(items[index], focusNode: node, onFocus: onFocus),
    );
  }
}
