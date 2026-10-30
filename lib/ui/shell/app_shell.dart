import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../download_converter.dart';
import '../../download_overview.dart';
import '../../follow_updater.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../explore/explore_page.dart';
import '../explore/source_actions.dart';
import '../follow/follow_page.dart';
import '../mine/mine_page.dart';
import '../update_prompt.dart';
import '../widgets/bar_button.dart';
import '../widgets/focus_ring.dart';
import '../widgets/source_bar.dart';

enum AppTab {
  explore('发现', Icons.explore_outlined, Icons.explore),
  follow('追剧', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
  mine('我的', Icons.person_outline_rounded, Icons.person_rounded);

  const AppTab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

Future<T?> openPage<T>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(
      context,
      rootNavigator: switch (AppScope.formFactorOf(context)) {
        FormFactor.phone || FormFactor.television => true,
        FormFactor.pad || FormFactor.window => false,
      },
    ).push(MaterialPageRoute<T>(builder: builder));

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});
  final LocalStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _navigators = [
    for (final _ in AppTab.values) GlobalKey<NavigatorState>(),
  ];
  final _tabFocus = [for (final _ in AppTab.values) FocusNode()];
  final _followEntry = FocusNode();
  final _mineEntry = FocusNode();
  final _header = FocusNode();
  final _televisionTabs = GlobalKey();
  final _explore = GlobalKey<ExplorePageState>();
  var _tab = AppTab.explore;
  var _headerFocused = false;
  FocusNode? _lastFocus;
  Timer? _exitWindow;
  DownloadOverview? _downloads;
  DownloadConverter? _converter;
  FollowUpdater? _followUpdater;

  NavigatorState? get _navigator => _navigators[_tab.index].currentState;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_followFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runStartupChecks(context, widget.store);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _downloads ??= DownloadOverview(
      AppScope.of(context).repository,
      widget.store,
    );
    _converter ??= DownloadConverter(
      AppScope.of(context).repository,
      _downloads!,
    );
    _followUpdater ??= FollowUpdater(
      AppScope.of(context).repository,
      widget.store,
    )..start();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_followFocus);
    for (final node in _tabFocus) {
      node.dispose();
    }
    _followEntry.dispose();
    _mineEntry.dispose();
    _header.dispose();
    _exitWindow?.cancel();
    _converter?.dispose();
    _downloads?.dispose();
    _followUpdater?.dispose();
    super.dispose();
  }

  void _select(AppTab tab) => setState(() => _tab = tab);

  void _followFocus() {
    final previous = _lastFocus;
    final focused = _lastFocus = FocusManager.instance.primaryFocus;
    final index = _tabFocus.indexWhere((node) => node == focused);
    if (index < 0) return;
    if (previous?.ancestors.contains(_header) ?? false) {
      _select(AppTab.values[index]);
    } else if (index != _tab.index) {
      _tabFocus[_tab.index].requestFocus();
    }
  }

  Future<void> _back() async {
    final navigator = _navigator;
    if (navigator != null && await navigator.maybePop()) return;
    if (!mounted) return;
    final television = AppScope.of(context).television;
    if (_tab == AppTab.explore && (!television || _headerFocused)) {
      _armExit();
      return;
    }
    if (_tab == AppTab.explore) _explore.currentState?.refresh();
    _select(AppTab.explore);
    if (television) _tabFocus.first.requestFocus();
  }

  void _armExit() {
    const window = Duration(seconds: 2);
    setState(() {
      _exitWindow = Timer(window, () {
        if (mounted) setState(() => _exitWindow = null);
      });
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('再按一次返回退出应用'), duration: window),
      );
  }

  Widget _root(AppTab tab) => switch (tab) {
    AppTab.explore => ExplorePage(key: _explore, store: widget.store),
    AppTab.follow => FollowPage(
      store: widget.store,
      entryFocus: _followEntry,
      onExitUp: _tabFocus[AppTab.follow.index].requestFocus,
    ),
    AppTab.mine => MinePage(
      store: widget.store,
      downloads: _downloads!,
      converter: _converter!,
      entryFocus: _mineEntry,
      onExitUp: _tabFocus[AppTab.mine.index].requestFocus,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final pages = NotificationListener<NavigationNotification>(
      onNotification: (_) {
        setState(() {});
        return false;
      },
      child: IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in AppTab.values)
            Navigator(
              key: _navigators[tab.index],
              routeTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
              routeDirectionalTraversalEdgeBehavior:
                  TraversalEdgeBehavior.parentScope,
              onGenerateInitialRoutes: (_, _) => [
                MaterialPageRoute<void>(builder: (_) => _root(tab)),
              ],
            ),
        ],
      ),
    );
    final television = AppScope.of(context).television;
    final covered = _navigator?.canPop() ?? false;
    return PopScope(
      canPop:
          _exitWindow != null &&
          _tab == AppTab.explore &&
          !covered &&
          (!television || _headerFocused),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: switch (AppScope.formFactorOf(context)) {
        FormFactor.phone => Scaffold(
          body: pages,
          bottomNavigationBar: covered
              ? null
              : NavigationBar(
                  selectedIndex: _tab.index,
                  onDestinationSelected: (index) =>
                      _select(AppTab.values[index]),
                  destinations: [
                    for (final tab in AppTab.values)
                      NavigationDestination(
                        key: ValueKey('nav-${tab.name}'),
                        icon: _badged(tab, Icon(tab.icon)),
                        selectedIcon: _badged(tab, Icon(tab.selectedIcon)),
                        label: tab.label,
                      ),
                  ],
                ),
        ),
        FormFactor.pad || FormFactor.window => _wide(pages),
        FormFactor.television => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                if (!covered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      televisionInset,
                      27,
                      televisionInset,
                      8,
                    ),
                    child: Focus(
                      focusNode: _header,
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (focused) =>
                          setState(() => _headerFocused = focused),
                      onKeyEvent: (_, event) {
                        final entry = switch (_tab) {
                          AppTab.follow => _followEntry,
                          AppTab.mine => _mineEntry,
                          AppTab.explore => null,
                        };
                        if (event is KeyUpEvent ||
                            event.logicalKey != LogicalKeyboardKey.arrowDown ||
                            entry?.context == null) {
                          return KeyEventResult.ignored;
                        }
                        revealFocus(entry!);
                        return KeyEventResult.handled;
                      },
                      child: _televisionHeader(),
                    ),
                  ),
                Expanded(child: pages),
              ],
            ),
          ),
        ),
      },
    );
  }

  Widget _badged(AppTab tab, Widget icon) => tab == AppTab.mine
      ? _DownloadBadge(downloads: _downloads!, child: icon)
      : icon;

  Widget _televisionHeader() {
    final tabs = Row(
      key: _televisionTabs,
      spacing: 6,
      children: [
        for (final tab in AppTab.values)
          _TelevisionTab(
            tab: tab,
            selected: tab == _tab,
            focusNode: _tabFocus[tab.index],
            onTap: () => _select(tab),
          ),
      ],
    );
    final store = widget.store;
    if (store.source.isEmpty) {
      return SizedBox(height: 48, child: tabs);
    }
    final source = SourceSite.byId(store.source);
    return SourceBar(
      source: source.name,
      televisionLeading: tabs,
      onSwitchSource: (anchor) => pickSource(anchor, store),
      onOpenSearch: () => openSearch(context, store, source),
      onSearchSubmitted: (query) =>
          openSearch(context, store, source, query: query),
    );
  }

  Widget _wide(Widget pages) {
    final roomy = MediaQuery.sizeOf(context).width >= 840;
    final expanded = roomy && widget.store.sideBarExpanded;
    return Scaffold(
      body: Row(
        children: [
          _SideBar(
            selected: _tab,
            expanded: expanded,
            badged: _badged,
            onSelect: _select,
            onToggle: roomy
                ? () => widget.store.setSideBarExpanded(!expanded)
                : null,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: pages,
            ),
          ),
        ],
      ),
    );
  }
}

typedef _SideMetrics = ({
  double width,
  double inset,
  double top,
  double menuGap,
  double spacing,
  double itemHeight,
  double iconSize,
  double labelSize,
  EdgeInsets labelPadding,
});

_SideMetrics _sideMetrics({required bool desktop, required bool expanded}) =>
    desktop
    ? (
        width: expanded ? 240 : 80,
        inset: 12,
        top: 12,
        menuGap: 8,
        spacing: 4,
        itemHeight: 48,
        iconSize: 22,
        labelSize: 14,
        labelPadding: const EdgeInsets.fromLTRB(17, 0, 16, 0),
      )
    : (
        width: expanded ? 232 : 88,
        inset: 16,
        top: 8,
        menuGap: 12,
        spacing: 4,
        itemHeight: 56,
        iconSize: 24,
        labelSize: 15,
        labelPadding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
      );

class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.selected,
    required this.expanded,
    required this.badged,
    required this.onSelect,
    this.onToggle,
  });
  final AppTab selected;
  final bool expanded;
  final Widget Function(AppTab tab, Widget icon) badged;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final metrics = _sideMetrics(
      desktop: AppScope.formFactorOf(context) == FormFactor.window,
      expanded: expanded,
    );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        right: false,
        child: SizedBox(
          key: const ValueKey('side-bar'),
          width: metrics.width,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.inset,
              metrics.top,
              metrics.inset,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: metrics.spacing,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: metrics.menuGap),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 56,
                      height: 48,
                      child: onToggle == null
                          ? null
                          : Center(
                              child: BarButton(
                                icon: Icons.menu_rounded,
                                tooltip: expanded ? '收起侧栏' : '展开侧栏',
                                onPressed: onToggle,
                              ),
                            ),
                    ),
                  ),
                ),
                for (final tab in AppTab.values)
                  _SideItem(
                    tab: tab,
                    selected: tab == selected,
                    expanded: expanded,
                    metrics: metrics,
                    badged: badged,
                    onTap: () => onSelect(tab),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.tab,
    required this.selected,
    required this.expanded,
    required this.metrics,
    required this.badged,
    required this.onTap,
  });
  final AppTab tab;
  final bool selected;
  final bool expanded;
  final _SideMetrics metrics;
  final Widget Function(AppTab tab, Widget icon) badged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final icon = badged(
      tab,
      Icon(
        selected ? tab.selectedIcon : tab.icon,
        color: color,
        size: metrics.iconSize,
      ),
    );
    final item = Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('nav-${tab.name}'),
        onTap: onTap,
        child: SizedBox(
          height: metrics.itemHeight,
          child: expanded
              ? Padding(
                  padding: metrics.labelPadding,
                  child: Row(
                    spacing: 12,
                    children: [
                      icon,
                      Expanded(
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: metrics.labelSize,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Center(child: icon),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      child: FocusRing(
        radius: metrics.itemHeight / 2,
        child: expanded ? item : Tooltip(message: tab.label, child: item),
      ),
    );
  }
}

class _DownloadBadge extends StatelessWidget {
  const _DownloadBadge({required this.downloads, required this.child});
  final DownloadOverview downloads;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: downloads,
    builder: (context, child) {
      final count = downloads.active;
      return Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: child,
      );
    },
    child: child,
  );
}

class _TelevisionTab extends StatelessWidget {
  const _TelevisionTab({
    required this.tab,
    required this.selected,
    required this.focusNode,
    required this.onTap,
  });
  final AppTab tab;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      child: FocusPill(
        focusNode: focusNode,
        selected: selected,
        textStyle: theme.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        child: InkWell(
          key: ValueKey('nav-${tab.name}'),
          focusNode: focusNode,
          autofocus: tab == AppTab.explore,
          focusColor: Colors.transparent,
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Text(tab.label),
          ),
        ),
      ),
    );
  }
}
