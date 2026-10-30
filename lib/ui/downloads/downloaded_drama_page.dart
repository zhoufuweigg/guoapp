import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app_device.dart';
import '../../core_bridge.dart';
import '../../download_collections.dart';
import '../../download_export.dart';
import '../../download_merge.dart';
import '../../download_overview.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../player/playback_handle.dart';
import '../player/playback_page.dart';
import '../widgets/cover_image.dart';
import '../widgets/focus_ring.dart';
import '../widgets/status_view.dart';
import 'download_actions.dart';
import 'merge_dialog.dart';

class DownloadedDramaPage extends StatefulWidget {
  const DownloadedDramaPage({
    super.key,
    required this.store,
    required this.downloads,
    required this.drama,
  });
  final LocalStore store;
  final DownloadOverview downloads;
  final Drama drama;

  @override
  State<DownloadedDramaPage> createState() => _DownloadedDramaPageState();
}

class _DownloadedDramaPageState extends State<DownloadedDramaPage> {
  DownloadCollectionUpdater? _updater;
  Set<String>? _selection;
  bool _busy = false;
  bool _playing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updater ??= DownloadCollectionUpdater(
      AppScope.of(context).repository,
      widget.store,
    );
  }

  @override
  void dispose() {
    _updater?.dispose();
    super.dispose();
  }

  Future<void> _fill(Drama drama) async {
    final updater = _updater!;
    final inspection = updater.inspect(drama, widget.downloads.jobs)..ignore();
    final plan = await showDialog<DownloadFill>(
      context: context,
      builder: (context) => _FillDialog(inspection: inspection),
    );
    if (plan == null || !mounted) return;
    await updater.fill(plan);
    if (!mounted) return;
    showMessage(context, updater.error ?? updater.status);
    await widget.downloads.refresh();
  }

  Future<void> _remove(DownloadedDrama item, Set<String> ids) async {
    if (ids.isEmpty ||
        !await confirmRemoval(
          context,
          title: '删除 ${ids.length} 集？',
          message: '视频文件会一起删除。',
          action: '删除',
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final removed = await removeDownloads(context, ids.toList(), done: '已删除');
    await widget.downloads.refresh();
    if (!mounted) return;
    if (removed && ids.length == item.episodes.length) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _selection = null;
      });
    }
  }

  Future<void> _merge(DownloadedDrama item, Set<String> ids) async {
    setState(() => _busy = true);
    await mergeDownloads(context, [
      for (final job in item.episodes)
        if (ids.contains(job.id)) job,
    ]);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export(DownloadedDrama item, Set<String> ids) async {
    final repository = AppScope.of(context).repository;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final jobs = [
      for (final job in item.episodes)
        if (ids.contains(job.id)) job,
    ];
    try {
      if (!await AppDevice.requestVideoExport()) {
        throw AppFailure('未获得存储权限，无法导出');
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
      return;
    }
    if (!mounted) return;
    final delete = widget.store.deleteAfterManualExport;
    final exported = ValueNotifier(0);
    setState(() => _busy = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('导出到 Movies'),
          content: ValueListenableBuilder(
            valueListenable: exported,
            builder: (context, count, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Text('已导出 $count / ${jobs.length} 集'),
                LinearProgressIndicator(value: count / jobs.length),
              ],
            ),
          ),
        ),
      ),
    );
    final failures = <String>[];
    for (final job in jobs) {
      try {
        await exportDownload(repository, job, delete: delete);
        exported.value++;
      } catch (error) {
        failures.add('$error');
      }
    }
    navigator.pop();
    await widget.downloads.refresh();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? '已导出到 Movies/${safeFileName(item.drama.title)}'
              : '${failures.length} 集未能导出：${failures.first}',
        ),
      ),
    );
    if (!mounted) return;
    if (delete && exported.value == item.episodes.length) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _selection = null;
      });
    }
  }

  Future<void> _play(DownloadedDrama item, int index) async {
    if (_playing) return;
    _playing = true;
    final episode = item.episodes[index].episode;
    final watch = widget.store.watched(item.drama.id);
    final position = watch?.episode == episode.number && !watch!.finished
        ? watch.position
        : 0.0;
    final handle = PlaybackHandle(
      repository: AppScope.of(context).repository,
      store: widget.store,
      detail: DramaDetail(item.drama, [
        for (final job in item.episodes) job.episode,
      ]),
      index: index,
      position: position,
      preopen: widget.store.playbackPreferences.preopens(
        television: AppScope.of(context).television,
      ),
    );
    handle.session.start(index, position: position);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaybackPage(store: widget.store, handle: handle),
      ),
    );
    _playing = false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, widget.downloads, _updater]),
    builder: (context, _) {
      final item = downloadedDramas(
        widget.downloads.jobs,
      ).where((entry) => entry.drama.id == widget.drama.id).firstOrNull;
      final selection = item == null
          ? null
          : _selection?.intersection({for (final job in item.episodes) job.id});
      final phone = AppScope.formFactorOf(context) == FormFactor.phone;
      return PopScope(
        canPop: _selection == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selection = null);
        },
        child: phone
            ? _phone(context, item, selection)
            : _wide(context, item, selection),
      );
    },
  );

  Widget _textButton(String label, VoidCallback? onPressed, {IconData? icon}) =>
      FocusRing(
        radius: 20,
        child: icon == null
            ? TextButton(onPressed: onPressed, child: Text(label))
            : TextButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(label),
              ),
      );

  Widget _fillButton(Drama drama, {bool icon = true}) => _textButton(
    '补齐缺集',
    _updater!.busy || _busy ? null : () => _fill(drama),
    icon: icon ? Icons.refresh_rounded : null,
  );

  Widget _editButton(DownloadedDrama? item, {bool icon = true}) => _textButton(
    '编辑',
    item == null ? null : () => setState(() => _selection = {}),
    icon: icon ? Icons.check_box_outlined : null,
  );

  Widget _selectAll(DownloadedDrama item, Set<String> selection) {
    final all = {for (final job in item.episodes) job.id};
    final everything = selection.length == all.length;
    return _textButton(
      everything ? '取消全选' : '全选',
      () => setState(() => _selection = everything ? {} : all),
    );
  }

  Widget _mergeButton(DownloadedDrama item, Set<String> selection) => FocusRing(
    radius: 20,
    child: FilledButton.tonalIcon(
      onPressed: selection.length < 2 || _busy
          ? null
          : () => _merge(item, selection),
      icon: const Icon(Icons.merge_rounded, size: 18),
      label: const Text('合并'),
    ),
  );

  Widget _exportButton(DownloadedDrama item, Set<String> selection) =>
      FocusRing(
        radius: 20,
        child: FilledButton.tonalIcon(
          onPressed: selection.isEmpty || _busy
              ? null
              : () => _export(item, selection),
          icon: const Icon(Icons.drive_folder_upload_outlined, size: 18),
          label: const Text('导出'),
        ),
      );

  Widget _deleteButton(DownloadedDrama item, Set<String> selection) {
    final colors = Theme.of(context).colorScheme;
    return FocusRing(
      radius: 20,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
        ),
        onPressed: selection.isEmpty || _busy
            ? null
            : () => _remove(item, selection),
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: const Text('删除'),
      ),
    );
  }

  Widget _phone(
    BuildContext context,
    DownloadedDrama? item,
    Set<String>? selection,
  ) {
    final drama = item?.drama ?? widget.drama;
    return Scaffold(
      appBar: selection == null || item == null
          ? AppBar(
              title: Text(drama.title),
              actions: [
                _fillButton(drama, icon: false),
                _editButton(item, icon: false),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              leading: IconButton(
                tooltip: '退出编辑',
                onPressed: () => setState(() => _selection = null),
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text('已选择 ${selection.length} 集'),
              actions: [_selectAll(item, selection), const SizedBox(width: 8)],
            ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: _content(context, item, selection, inset: 16),
      ),
      bottomNavigationBar: selection == null || item == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Expanded(child: _mergeButton(item, selection)),
                      if (Platform.isAndroid)
                        Expanded(child: _exportButton(item, selection)),
                      Expanded(child: _deleteButton(item, selection)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _wide(
    BuildContext context,
    DownloadedDrama? item,
    Set<String>? selection,
  ) {
    final drama = item?.drama ?? widget.drama;
    final editing = selection != null && item != null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 24, 8),
              child: SizedBox(
                height: 48,
                child: Row(
                  spacing: 8,
                  children: [
                    if (editing)
                      IconButton(
                        tooltip: '退出编辑',
                        onPressed: () => setState(() => _selection = null),
                        icon: const Icon(Icons.close_rounded),
                      )
                    else
                      const BackButton(),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          editing ? '已选择 ${selection.length} 集' : drama.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (editing) ...[
                      _selectAll(item, selection),
                      _mergeButton(item, selection),
                      if (Platform.isAndroid) _exportButton(item, selection),
                      _deleteButton(item, selection),
                      _textButton(
                        '完成',
                        () => setState(() => _selection = null),
                      ),
                    ] else ...[
                      _fillButton(drama),
                      _editButton(item),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: _content(context, item, selection, inset: 24, lead: 68),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    DownloadedDrama? item,
    Set<String>? selection, {
    required double inset,
    double? lead,
  }) {
    final colors = Theme.of(context).colorScheme;
    final updater = _updater!;
    final header = <Widget>[
      if (item != null)
        Padding(
          padding: EdgeInsets.fromLTRB(lead ?? inset, 4, inset, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SourceTag(item.drama.source),
              Text(
                '已下载 ${item.episodes.length} 集 · ${formatBytes(item.bytes)}'
                '${item.pending > 0 ? ' · 另有 ${item.pending} 集在下载中' : ''}',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      if (updater.busy)
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 8, inset, 0),
          child: Material(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Text(
                      updater.status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ),
                  _textButton('停止', updater.cancel),
                ],
              ),
            ),
          ),
        ),
    ];
    if (item == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          const Expanded(
            child: StatusView(
              title: '没有已下载的剧集',
              icon: Icons.download_done_rounded,
            ),
          ),
        ],
      );
    }
    return _EpisodeList(
      header: header,
      episodes: item.episodes,
      watched: widget.store.watched(item.drama.id)?.episode,
      selection: selection,
      inset: inset,
      touch: AppScope.formFactorOf(context) != FormFactor.window,
      onSelect: (selection) => setState(() => _selection = selection),
      onPlay: (index) => _play(item, index),
    );
  }
}

const _cardHeight = 64.0;
const _cardGap = 12.0;
const _rowExtent = _cardHeight + _cardGap;
const _gridTop = 12.0;

class _EpisodeList extends StatefulWidget {
  const _EpisodeList({
    required this.header,
    required this.episodes,
    required this.watched,
    required this.selection,
    required this.inset,
    required this.touch,
    required this.onSelect,
    required this.onPlay,
  });
  final List<Widget> header;
  final List<DownloadJob> episodes;
  final int? watched;
  final Set<String>? selection;
  final double inset;
  final bool touch;
  final ValueChanged<Set<String>> onSelect;
  final ValueChanged<int> onPlay;

  @override
  State<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<_EpisodeList> {
  final _scroll = ScrollController();
  final _headerKey = GlobalKey();
  bool? _dragAdds;
  bool _marked = false;
  bool _swallowTap = false;
  int _dragAnchor = 0;
  Set<String> _dragBase = const {};
  Offset? _dragPoint;
  Timer? _autoScroll;
  double _width = 0;
  double _height = 0;
  int _columns = 1;

  List<DownloadJob> get _episodes => widget.episodes;

  @override
  void didUpdateWidget(_EpisodeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selection == null) _dragEnd();
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  double get _top => (_headerKey.currentContext?.size?.height ?? 0) + _gridTop;

  double get _cardWidth =>
      (_width - widget.inset * 2 - _cardGap * (_columns - 1)) / _columns;

  int? _hit(Offset point, {bool exact = false}) {
    if (_episodes.isEmpty || !_scroll.hasClients) return null;
    final pitch = _cardWidth + _cardGap;
    final x = point.dx - widget.inset;
    final y = point.dy + _scroll.offset - _top;
    if (exact &&
        (x < 0 ||
            y < 0 ||
            x >= pitch * _columns ||
            x % pitch > _cardWidth ||
            y % _rowExtent > _cardHeight)) {
      return null;
    }
    final rows = (_episodes.length / _columns).ceil();
    final column = (x / pitch).floor().clamp(0, _columns - 1);
    final row = (y / _rowExtent).floor().clamp(0, rows - 1);
    final index = row * _columns + column;
    if (index < _episodes.length) return index;
    return exact ? null : _episodes.length - 1;
  }

  void _mark(int index) {
    final adds = _dragAdds;
    if (adds == null) return;
    _marked = true;
    final range = {
      for (
        var item = min(index, _dragAnchor);
        item <= max(index, _dragAnchor);
        item++
      )
        _episodes[item].id,
    };
    widget.onSelect(
      adds ? _dragBase.union(range) : _dragBase.difference(range),
    );
  }

  void _toggle(int index) {
    if (_swallowTap) return;
    final selection = {...?widget.selection};
    final id = _episodes[index].id;
    if (!selection.remove(id)) selection.add(id);
    widget.onSelect(selection);
  }

  void _dragStart(Offset point) {
    final selection = widget.selection;
    final index = _hit(point, exact: true);
    if (selection == null || index == null) return;
    _dragAdds = !selection.contains(_episodes[index].id);
    _dragAnchor = index;
    _dragBase = selection;
    _dragPoint = point;
    if (widget.touch) _mark(index);
  }

  void _dragMove(Offset point) {
    if (_dragAdds == null) return;
    _dragPoint = point;
    final index = _hit(point);
    if (index != null && (_marked || index != _dragAnchor)) _mark(index);
    if (_marked && _edgeSpeed(point.dy) != 0) {
      _autoScroll ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _autoScrollTick(),
      );
    }
  }

  void _pointerUp() {
    _swallowTap = _marked;
    scheduleMicrotask(() => _swallowTap = false);
    _dragEnd();
  }

  void _dragEnd() {
    _dragAdds = null;
    _dragPoint = null;
    _marked = false;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  double _edgeSpeed(double y) {
    const zone = 64.0;
    final depth = y < zone
        ? y - zone
        : y > _height - zone
        ? y - (_height - zone)
        : 0.0;
    if (depth == 0) return 0;
    final t = (depth.abs() / zone).clamp(0.0, 2.0) / 2;
    return depth.sign * (120 + 1700 * t * t);
  }

  void _autoScrollTick() {
    final point = _dragPoint;
    final speed = point == null ? 0.0 : _edgeSpeed(point.dy);
    if (speed == 0 || !_scroll.hasClients) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    final position = _scroll.position;
    final next = (position.pixels + speed * .016).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) return;
    _scroll.jumpTo(next);
    final index = _hit(point!);
    if (index != null) _mark(index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      _height = constraints.maxHeight;
      _columns =
          ((_width - widget.inset * 2 + _cardGap) /
                  ((widget.inset == 16 ? 160 : 220) + _cardGap))
              .floor()
              .clamp(1, 99);
      final selection = widget.selection;
      final selecting = selection != null;
      final list = CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _headerKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.header,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              widget.inset,
              _gridTop,
              widget.inset,
              32,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                crossAxisSpacing: _cardGap,
                mainAxisSpacing: _cardGap,
                mainAxisExtent: _cardHeight,
              ),
              itemCount: _episodes.length,
              itemBuilder: (context, index) {
                final job = _episodes[index];
                return _EpisodeCard(
                  key: ValueKey(job.id),
                  job: job,
                  watching: !selecting && job.episode.number == widget.watched,
                  selected: selection?.contains(job.id),
                  onTap: selecting
                      ? () => _toggle(index)
                      : () => widget.onPlay(index),
                );
              },
            ),
          ),
        ],
      );
      if (widget.touch) {
        return GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: selecting
              ? (details) => _dragStart(details.localPosition)
              : null,
          onHorizontalDragUpdate: selecting
              ? (details) => _dragMove(details.localPosition)
              : null,
          onHorizontalDragEnd: selecting ? (_) => _dragEnd() : null,
          onHorizontalDragCancel: selecting ? _dragEnd : null,
          child: list,
        );
      }
      return Listener(
        onPointerDown: selecting
            ? (event) => _dragStart(event.localPosition)
            : null,
        onPointerMove: selecting
            ? (event) => _dragMove(event.localPosition)
            : null,
        onPointerUp: (_) => _pointerUp(),
        onPointerCancel: (_) => _dragEnd(),
        child: list,
      );
    },
  );
}

class _FillDialog extends StatelessWidget {
  const _FillDialog({required this.inspection});
  final Future<DownloadFill> inspection;

  Widget _button(
    BuildContext context,
    String label, {
    DownloadFill? result,
    bool primary = false,
  }) => FocusRing(
    radius: 20,
    child: primary
        ? FilledButton(
            onPressed: () => Navigator.pop(context, result),
            child: Text(label),
          )
        : TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, result),
            child: Text(label),
          ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<DownloadFill>(
    future: inspection,
    builder: (context, snapshot) {
      final plan = snapshot.data;
      final Widget content;
      final List<Widget> actions;
      if (snapshot.hasError) {
        content = Text('${snapshot.error}');
        actions = [_button(context, '关闭')];
      } else if (plan == null) {
        content = const Row(
          spacing: 16,
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            Text('正在读取最新分集…'),
          ],
        );
        actions = [_button(context, '取消')];
      } else {
        final vip = plan.skippedVip > 0
            ? '\n另有 ${plan.skippedVip} 集 VIP，下载设置里没有包含 VIP 集，不会加入。'
            : '';
        content = Text(
          plan.missing == 0
              ? '本剧已全部下载，没有需要补齐的集。$vip'
              : '本剧还有 ${plan.missing} 集没有下载，确认后加入下载。$vip',
        );
        actions = plan.missing == 0
            ? [_button(context, '知道了')]
            : [
                _button(context, '取消'),
                _button(
                  context,
                  '补齐 ${plan.missing} 集',
                  result: plan,
                  primary: true,
                ),
              ];
      }
      return AlertDialog(
        title: const Text('补齐缺集'),
        content: content,
        actions: actions,
      );
    },
  );
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    super.key,
    required this.job,
    required this.watching,
    required this.selected,
    required this.onTap,
  });
  final DownloadJob job;
  final bool watching;
  final bool? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final episode = job.episode;
    final meta = job.actualQuality > 0
        ? '${job.actualQuality}P · ${formatBytes(job.bytes)}'
        : formatBytes(job.bytes);
    return Semantics(
      button: true,
      checked: selected,
      label:
          '第 ${episode.number} 集${episode.vip ? '，VIP' : ''}'
          '${watching ? '，看到这里' : ''}，$meta',
      excludeSemantics: true,
      child: FocusRing(
        radius: 14,
        child: Material(
          color: colors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: selected == true
                ? BorderSide(color: colors.primary, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(selected == null ? 16 : 8, 8, 12, 8),
              child: Row(
                spacing: 8,
                children: [
                  if (selected case final selected?)
                    Checkbox(value: selected, onChanged: (_) => onTap()),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Row(
                          spacing: 6,
                          children: [
                            Text(
                              '第 ${episode.number} 集',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (episode.vip) const VipBadge(),
                            if (watching)
                              Flexible(
                                child: Text(
                                  '看到这里',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected == null)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: colors.onSurface,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
