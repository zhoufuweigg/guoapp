import 'package:flutter/material.dart';

import '../../local_store.dart';
import '../../models.dart';
import '../../watch_history.dart';
import '../app_scope.dart';
import '../detail/detail_page.dart';
import '../settings/settings_rows.dart';
import '../shell/app_shell.dart';
import '../widgets/drama_grid.dart';
import '../widgets/drama_tile.dart';
import '../widgets/focus_ring.dart';
import '../widgets/search_field.dart';
import '../widgets/status_view.dart';

typedef _View = ({
  List<WatchEntry> history,
  List<SourceSite> sources,
  String source,
  List<WatchEntry> shown,
  Set<String>? selection,
});

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store});
  final LocalStore store;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _query = TextEditingController();
  final _firstPoster = FocusNode();
  final _editButton = FocusNode();
  final _searchField = FocusNode();
  var _source = '';
  Set<String>? _selection;

  @override
  void initState() {
    super.initState();
    _keepFocus(_firstPoster);
  }

  @override
  void dispose() {
    _query.dispose();
    _firstPoster.dispose();
    _editButton.dispose();
    _searchField.dispose();
    super.dispose();
  }

  void _keepFocus(FocusNode target, [FocusNode? fallback]) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !AppScope.of(context).television) return;
        final focused = FocusManager.instance.primaryFocus;
        if (focused != null && focused is! FocusScopeNode) return;
        for (final node in [target, ?fallback]) {
          if (node.context?.mounted ?? false) {
            revealFocus(node);
            return;
          }
        }
      });

  void _startEditing() {
    setState(() => _selection = {});
    _keepFocus(_firstPoster);
  }

  void _finishEditing() {
    setState(() => _selection = null);
    _keepFocus(_editButton);
  }

  void _toggle(String id) => setState(() {
    final selection = {...?_selection};
    if (!selection.remove(id)) selection.add(id);
    _selection = selection;
  });

  Future<void> _remove(Set<String> ids, {required bool clear}) async {
    if (ids.isEmpty) return;
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(clear ? '清空观看记录？' : '删除 ${ids.length} 条观看记录？'),
        content: Text(
          clear ? '将删除当前列出的 ${ids.length} 条观看记录，追剧不受影响。' : '追剧不受影响。',
        ),
        actions: [
          FocusRing(
            radius: 20,
            child: TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
          ),
          FocusRing(
            radius: 20,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(clear ? '清空' : '删除'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await saveSetting(context, () => widget.store.removeHistory(ids));
    if (!mounted) return;
    setState(() => _selection = null);
    _keepFocus(_firstPoster, _searchField);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, _query]),
    builder: (context, _) {
      final history = widget.store.history;
      final sources = watchedSources(history);
      final source = sources.any((site) => site.id == _source) ? _source : '';
      final shown = [
        for (final entry in history)
          if ((source.isEmpty || entry.drama.source == source) &&
              matchesWatchTitle(entry, _query.text))
            entry,
      ];
      final view = (
        history: history,
        sources: sources,
        source: source,
        shown: shown,
        selection: _selection?.intersection({
          for (final entry in shown) entry.drama.id,
        }),
      );
      return PopScope(
        canPop: _selection == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _finishEditing();
        },
        child: switch (AppScope.formFactorOf(context)) {
          FormFactor.phone => _phone(context, view),
          FormFactor.pad || FormFactor.window => _wide(context, view),
          FormFactor.television => _television(context, view),
        },
      );
    },
  );

  Set<String> _ids(_View view) => {
    for (final entry in view.shown) entry.drama.id,
  };

  Widget _search({double height = 40, FocusNode? focusNode}) => SearchField(
    hint: '搜索观看记录',
    controller: _query,
    focusNode: focusNode,
    height: height,
    onSubmitted: (_) {},
    letterKeyboard: widget.store.televisionKeyboard,
    matches: (query) async => {
      for (final entry in widget.store.history)
        if (matchesWatchTitle(entry, query)) entry.drama.title,
    }.toList(),
  );

  Widget _textButton(
    String label,
    VoidCallback? onPressed, {
    IconData? icon,
    FocusNode? focusNode,
  }) => FocusRing(
    radius: 20,
    child: icon == null
        ? TextButton(
            focusNode: focusNode,
            onPressed: onPressed,
            child: Text(label),
          )
        : TextButton.icon(
            focusNode: focusNode,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
  );

  List<Widget> _browseActions(_View view, {bool icons = true}) => [
    _textButton(
      '编辑',
      view.shown.isEmpty ? null : _startEditing,
      icon: icons ? Icons.check_box_outlined : null,
      focusNode: _editButton,
    ),
    _textButton(
      '清空',
      view.shown.isEmpty ? null : () => _remove(_ids(view), clear: true),
      icon: icons ? Icons.delete_outline_rounded : null,
    ),
  ];

  Widget _selectAll(_View view) {
    final all = _ids(view);
    final everything = view.selection!.length == all.length;
    return _textButton(
      everything ? '取消全选' : '全选',
      () => setState(() => _selection = everything ? {} : all),
    );
  }

  Widget _deleteButton(_View view) {
    final colors = Theme.of(context).colorScheme;
    final selection = view.selection!;
    return FocusRing(
      radius: 20,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
        ),
        onPressed: selection.isEmpty
            ? null
            : () => _remove(selection, clear: false),
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: const Text('删除'),
      ),
    );
  }

  List<Widget> _editActions(_View view) => [
    _selectAll(view),
    _deleteButton(view),
    _textButton('完成', _finishEditing),
  ];

  Widget _title(_View view, double size) => Semantics(
    header: true,
    child: Text(
      view.selection == null ? '观看记录' : '已选择 ${view.selection!.length} 部',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800),
    ),
  );

  Widget _sourceChip(String id, String label, _View view) => FocusRing(
    radius: 8,
    child: ChoiceChip(
      key: ValueKey('history-source-$id'),
      label: Text(label),
      showCheckmark: false,
      selected: view.source == id,
      onSelected: (_) => setState(() => _source = id),
    ),
  );

  Widget? _sources(_View view, {required double inset, bool scroll = false}) {
    if (view.sources.length < 2) return null;
    final chips = [
      _sourceChip('', '全部', view),
      for (final site in view.sources) _sourceChip(site.id, site.name, view),
    ];
    if (scroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(inset, 4, inset, 8),
        child: Row(spacing: 8, children: chips),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 4, inset, 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _phone(BuildContext context, _View view) {
    final selection = view.selection;
    return Scaffold(
      appBar: selection == null
          ? AppBar(
              title: const Text('观看记录'),
              actions: [
                ..._browseActions(view, icons: false),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              leading: IconButton(
                tooltip: '退出编辑',
                onPressed: _finishEditing,
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text('已选择 ${selection.length} 部'),
              actions: [_selectAll(view), const SizedBox(width: 8)],
            ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _content(
          context,
          view,
          inset: 16,
          header: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _search(),
            ),
            ?_sources(view, inset: 16, scroll: true),
          ],
        ),
      ),
      bottomNavigationBar: selection == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(height: 48, child: _deleteButton(view)),
              ),
            ),
    );
  }

  Widget _wide(BuildContext context, _View view) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: _content(
        context,
        view,
        inset: 24,
        header: [
          LayoutBuilder(
            builder: (context, constraints) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 24, 8),
              child: SizedBox(
                height: 48,
                child: Row(
                  spacing: 8,
                  children: [
                    if (view.selection == null)
                      const BackButton()
                    else
                      IconButton(
                        tooltip: '退出编辑',
                        onPressed: _finishEditing,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    Expanded(child: _title(view, 28)),
                    if (view.selection == null) ...[
                      SizedBox(
                        width: (constraints.maxWidth - 400).clamp(160.0, 280.0),
                        child: _search(),
                      ),
                      ..._browseActions(view),
                    ] else
                      ..._editActions(view),
                  ],
                ),
              ),
            ),
          ),
          ?_sources(view, inset: 24),
        ],
      ),
    ),
  );

  Widget _television(BuildContext context, _View view) => Scaffold(
    body: SafeArea(
      child: _content(
        context,
        view,
        inset: televisionInset,
        top: 27,
        header: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              televisionInset,
              0,
              televisionInset,
              8,
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                spacing: 12,
                children: [
                  Expanded(child: _title(view, 24)),
                  if (view.selection == null) ...[
                    SizedBox(
                      width: 260,
                      child: _search(focusNode: _searchField),
                    ),
                    ..._browseActions(view),
                  ] else
                    ..._editActions(view),
                ],
              ),
            ),
          ),
          ?_sources(view, inset: televisionInset),
        ],
      ),
    ),
  );

  (int, double, double) _grid(BuildContext context, double width) {
    switch (AppScope.formFactorOf(context)) {
      case FormFactor.phone:
        return (3, 10, 20);
      case FormFactor.television:
        return (6, 20, 24);
      case FormFactor.pad || FormFactor.window:
        final desktop = AppScope.formFactorOf(context) == FormFactor.window;
        final minimum = desktop ? 140.0 : 120.0;
        final gap = desktop ? 18.0 : 16.0;
        final columns = ((width + gap) / (minimum + gap)).floor().clamp(1, 99);
        return (columns, gap, desktop ? 22 : 20);
    }
  }

  Widget _content(
    BuildContext context,
    _View view, {
    required double inset,
    double top = 0,
    required List<Widget> header,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth - inset * 2;
      final (columns, gap, runGap) = _grid(context, width);
      final tile = (width - gap * (columns - 1)) / columns;
      final now = DateTime.now();
      final periods = <WatchPeriod, List<WatchEntry>>{};
      for (final entry in view.shown) {
        periods
            .putIfAbsent(WatchPeriod.of(entry.updatedAt, now), () => [])
            .add(entry);
      }
      final first = view.shown.firstOrNull;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: top),
            sliver: SliverList.list(children: header),
          ),
          if (view.shown.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: StatusView(
                title: view.history.isEmpty ? '还没有观看记录' : '没有匹配的记录',
                icon: view.history.isEmpty
                    ? Icons.history_rounded
                    : Icons.search_off_rounded,
              ),
            )
          else
            for (final MapEntry(key: period, value: entries)
                in periods.entries) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset + 4, 12, inset, 10),
                sliver: SliverToBoxAdapter(
                  child: Semantics(
                    header: true,
                    child: Text(
                      period.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: runGap,
                    mainAxisExtent: ProgressPoster.extentFor(context, tile),
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Focus(
                      key: ValueKey(entry.drama.id),
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: (_, event) =>
                          wrapGridRow(index, columns, entries.length, event),
                      child: _poster(
                        context,
                        entry,
                        tile,
                        view.selection,
                        focusNode: entry == first ? _firstPoster : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: AppScope.of(context).television ? 27 : 32,
            ),
          ),
        ],
      );
    },
  );

  Widget _poster(
    BuildContext context,
    WatchEntry entry,
    double width,
    Set<String>? selection, {
    FocusNode? focusNode,
  }) {
    final drama = entry.drama;
    final total = drama.episodes;
    final long = '看到第 ${entry.episode} 集 / 共 $total 集';
    return ProgressPoster(
      drama: drama,
      width: width,
      focusNode: focusNode,
      progress: total > 0 ? entry.episode / total : 0,
      caption: total > 0 && entry.episode >= total && entry.finished
          ? '已看完'
          : total > 0 && _fits(context, long, width)
          ? long
          : '看到第 ${entry.episode} 集',
      tag: SourceSite.byId(drama.source).name,
      selected: selection?.contains(drama.id),
      onTap: selection == null
          ? () => openPage<void>(
              context,
              (_) => DetailPage(store: widget.store, drama: drama),
            )
          : () => _toggle(drama.id),
    );
  }

  bool _fits(BuildContext context, String text, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.copyWith(
          fontSize: AppScope.of(context).television ? 13 : 12,
          height: 1.3,
        ),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final fits = painter.width <= width - 4;
    painter.dispose();
    return fits;
  }
}
