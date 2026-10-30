import 'package:flutter/material.dart';

import '../../download_collections.dart';
import '../../download_converter.dart';
import '../../download_overview.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../shell/app_shell.dart';
import '../widgets/cover_image.dart';
import '../widgets/drama_grid.dart';
import '../widgets/drama_tile.dart';
import '../widgets/focus_ring.dart';
import '../widgets/status_view.dart';
import 'download_actions.dart';
import 'downloaded_drama_page.dart';

typedef _View = ({
  List<DownloadJob> pending,
  List<DownloadedDrama> downloaded,
  List<SourceSite> sources,
  String source,
  Set<String>? selection,
});

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    required this.store,
    required this.downloads,
    required this.converter,
  });
  final LocalStore store;
  final DownloadOverview downloads;
  final DownloadConverter converter;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)
    ..addListener(_tabChanged);
  final _sources = ['', ''];
  Set<String>? _selection;
  bool _busy = false;

  bool get _pendingTab => _tabs.index == 0;

  @override
  void initState() {
    super.initState();
    widget.downloads.refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    setState(() => _selection = null);
  }

  void _toggle(String id) => setState(() {
    final selection = {...?_selection};
    if (!selection.remove(id)) selection.add(id);
    _selection = selection;
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) showMessage(context, error.toString());
    } finally {
      await widget.downloads.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _control(DownloadJob job) => _run(
    () => AppScope.of(
      context,
    ).repository.controlDownloads(job.active ? 'pause' : 'resume', id: job.id),
  );

  void _controlAll(String command, List<DownloadJob> jobs) => _run(() async {
    final repository = AppScope.of(context).repository;
    final result = await controlDownloadJobs(repository, command, [
      for (final job in jobs) job.id,
    ]);
    if (result.failures.isNotEmpty && mounted) {
      showMessage(
        context,
        '${result.failures.length} 集未能处理：${result.failures.values.first}',
      );
    }
  });

  Future<void> _cancel(Set<String> ids) async {
    if (ids.isEmpty ||
        !await confirmRemoval(
          context,
          title: '取消下载 ${ids.length} 集？',
          message: '已下载的部分会一起删除。',
          action: '取消下载',
        ) ||
        !mounted) {
      return;
    }
    await _run(() => removeDownloads(context, ids.toList(), done: '已取消下载'));
    if (mounted) setState(() => _selection = null);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.store,
      widget.downloads,
      widget.converter,
      _tabs,
    ]),
    builder: (context, _) {
      final jobs = widget.downloads.jobs;
      final index = _tabs.index;
      final sources = downloadSources(
        index == 0
            ? pendingDownloads(jobs)
            : [
                for (final job in jobs)
                  if (job.completed) job,
              ],
      );
      final source = sources.any((site) => site.id == _sources[index])
          ? _sources[index]
          : '';
      bool shown(Drama drama) => source.isEmpty || drama.source == source;
      final pending = [
        for (final job in pendingDownloads(jobs))
          if (shown(job.drama)) job,
      ];
      final view = (
        pending: pending,
        downloaded: [
          for (final drama in downloadedDramas(jobs))
            if (shown(drama.drama)) drama,
        ],
        sources: sources,
        source: source,
        selection: _selection?.intersection({
          for (final job in pending) job.id,
        }),
      );
      final body = !widget.downloads.available
          ? const StatusView(
              title: '当前用户没有下载权限',
              icon: Icons.lock_outline_rounded,
            )
          : index == 0
          ? _pendingList(context, view)
          : _downloadedGrid(context, view);
      return PopScope(
        canPop: _selection == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selection = null);
        },
        child: AppScope.formFactorOf(context) == FormFactor.phone
            ? _phone(context, view, body)
            : _wide(context, view, body),
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

  Widget _pauseAll(_View view, {bool icon = true}) {
    final active = [
      for (final job in view.pending)
        if (job.active) job,
    ];
    return _textButton(
      '全部暂停',
      active.isEmpty || _busy ? null : () => _controlAll('pause', active),
      icon: icon ? Icons.pause_rounded : null,
    );
  }

  Widget _resumeAll(_View view, {bool icon = true}) {
    final paused = [
      for (final job in view.pending)
        if (job.resumable) job,
    ];
    return _textButton(
      '全部继续',
      paused.isEmpty || _busy ? null : () => _controlAll('resume', paused),
      icon: icon ? Icons.play_arrow_rounded : null,
    );
  }

  Widget _editButton(_View view, {bool icon = true}) => _textButton(
    '编辑',
    view.pending.isEmpty ? null : () => setState(() => _selection = {}),
    icon: icon ? Icons.check_box_outlined : null,
  );

  Widget _selectAll(_View view) {
    final all = {for (final job in view.pending) job.id};
    final everything = view.selection!.length == all.length;
    return _textButton(
      everything ? '取消全选' : '全选',
      () => setState(() => _selection = everything ? {} : all),
    );
  }

  Widget _cancelButton(_View view) {
    final colors = Theme.of(context).colorScheme;
    final selection = view.selection!;
    return FocusRing(
      radius: 20,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
        ),
        onPressed: selection.isEmpty || _busy ? null : () => _cancel(selection),
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('取消下载'),
      ),
    );
  }

  Widget _tabBar(double inset) {
    final pending = pendingDownloads(widget.downloads.jobs).length;
    final downloaded = downloadedDramas(widget.downloads.jobs).length;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          Tab(text: pending == 0 ? '下载中' : '下载中 $pending'),
          Tab(text: downloaded == 0 ? '已下载' : '已下载 $downloaded'),
        ],
      ),
    );
  }

  Widget _phone(BuildContext context, _View view, Widget body) {
    final selection = view.selection;
    return Scaffold(
      appBar: selection == null
          ? AppBar(
              title: const Text('下载'),
              actions: [
                if (_pendingTab && view.pending.isNotEmpty) ...[
                  IconButton(
                    tooltip: '全部暂停',
                    onPressed: view.pending.any((job) => job.active) && !_busy
                        ? () => _controlAll('pause', [
                            for (final job in view.pending)
                              if (job.active) job,
                          ])
                        : null,
                    icon: const Icon(Icons.pause_rounded),
                  ),
                  IconButton(
                    tooltip: '全部继续',
                    onPressed:
                        view.pending.any((job) => job.resumable) && !_busy
                        ? () => _controlAll('resume', [
                            for (final job in view.pending)
                              if (job.resumable) job,
                          ])
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  _editButton(view, icon: false),
                ],
                const SizedBox(width: 8),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _tabBar(4),
              ),
            )
          : AppBar(
              leading: IconButton(
                tooltip: '退出编辑',
                onPressed: () => setState(() => _selection = null),
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text('已选择 ${selection.length} 集'),
              actions: [_selectAll(view), const SizedBox(width: 8)],
            ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?_sourceChips(view, inset: 16, scroll: true),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: selection == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(height: 48, child: _cancelButton(view)),
              ),
            ),
    );
  }

  Widget _wide(BuildContext context, _View view, Widget body) => Scaffold(
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
                  if (view.selection == null)
                    const BackButton()
                  else
                    IconButton(
                      tooltip: '退出编辑',
                      onPressed: () => setState(() => _selection = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        view.selection == null
                            ? '下载'
                            : '已选择 ${view.selection!.length} 集',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (view.selection != null) ...[
                    _selectAll(view),
                    _cancelButton(view),
                    _textButton('完成', () => setState(() => _selection = null)),
                  ] else if (_pendingTab && view.pending.isNotEmpty) ...[
                    _pauseAll(view),
                    _resumeAll(view),
                    _editButton(view),
                  ],
                ],
              ),
            ),
          ),
          _tabBar(24),
          const SizedBox(height: 8),
          ?_sourceChips(view, inset: 24),
          Expanded(child: body),
        ],
      ),
    ),
  );

  Widget? _sourceChips(
    _View view, {
    required double inset,
    bool scroll = false,
  }) {
    if (view.sources.length < 2) return null;
    Widget chip(String id, String label) => FocusRing(
      radius: 8,
      child: ChoiceChip(
        key: ValueKey('download-source-$id'),
        label: Text(label),
        showCheckmark: false,
        selected: view.source == id,
        onSelected: (_) => setState(() => _sources[_tabs.index] = id),
      ),
    );
    final chips = [
      chip('', '全部'),
      for (final site in view.sources) chip(site.id, site.name),
    ];
    if (scroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(inset, 8, inset, 4),
        child: Row(spacing: 8, children: chips),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 4),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _pendingList(BuildContext context, _View view) {
    if (view.pending.isEmpty) {
      return const StatusView(title: '没有正在下载的剧集', icon: Icons.download_rounded);
    }
    final phone = AppScope.formFactorOf(context) == FormFactor.phone;
    final inset = phone ? 16.0 : 24.0;
    final counts = <String, int>{};
    for (final job in view.pending) {
      counts[job.state] = (counts[job.state] ?? 0) + 1;
    }
    final summary = [
      for (final (state, label) in const [
        ('downloading', '下载中'),
        ('converting', '处理中'),
        ('queued', '等待'),
        ('paused', '已暂停'),
        ('failed', '失败'),
      ])
        if (counts[state] case final count?) '$label $count',
    ].join(' · ');
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 32),
      itemCount: view.pending.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 4 : 8),
      itemBuilder: (context, index) => index == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                summary,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : _JobRow(
              key: ValueKey(view.pending[index - 1].id),
              job: view.pending[index - 1],
              conversion: widget.converter.progressOf(
                view.pending[index - 1].id,
              ),
              selected: view.selection?.contains(view.pending[index - 1].id),
              busy: _busy,
              onToggle: () => _toggle(view.pending[index - 1].id),
              onControl: () => _control(view.pending[index - 1]),
            ),
    );
  }

  (int, double, double) _grid(BuildContext context, double width) {
    if (AppScope.formFactorOf(context) == FormFactor.phone) return (3, 10, 20);
    final desktop = AppScope.formFactorOf(context) == FormFactor.window;
    final minimum = desktop ? 140.0 : 120.0;
    final gap = desktop ? 18.0 : 16.0;
    final columns = ((width + gap) / (minimum + gap)).floor().clamp(1, 99);
    return (columns, gap, desktop ? 22 : 20);
  }

  Widget _downloadedGrid(BuildContext context, _View view) {
    if (view.downloaded.isEmpty) {
      return const StatusView(
        title: '没有下载完成的剧集',
        icon: Icons.download_done_rounded,
      );
    }
    final inset = AppScope.formFactorOf(context) == FormFactor.phone
        ? 16.0
        : 24.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - inset * 2;
        final (columns, gap, runGap) = _grid(context, width);
        final tile = (width - gap * (columns - 1)) / columns;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: runGap,
            mainAxisExtent: ProgressPoster.extentFor(context, tile),
          ),
          itemCount: view.downloaded.length,
          itemBuilder: (context, index) {
            final item = view.downloaded[index];
            return Focus(
              key: ValueKey(item.drama.id),
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, event) =>
                  wrapGridRow(index, columns, view.downloaded.length, event),
              child: ProgressPoster(
                drama: item.drama,
                width: tile,
                progress: null,
                caption:
                    '${item.episodes.length} 集 · ${formatBytes(item.bytes)}',
                tag: SourceSite.byId(item.drama.source).name,
                badge: item.pending > 0 ? '${item.pending} 集下载中' : null,
                onTap: () => openPage<void>(
                  context,
                  (_) => DownloadedDramaPage(
                    store: widget.store,
                    downloads: widget.downloads,
                    drama: item.drama,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    super.key,
    required this.job,
    required this.conversion,
    required this.selected,
    required this.busy,
    required this.onToggle,
    required this.onControl,
  });
  final DownloadJob job;
  final double? conversion;
  final bool? selected;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onControl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final downloading = job.state == 'downloading';
    final failed = job.state == 'failed';
    final converted = (conversion ?? 0) > 0 ? conversion : null;
    final state = downloading
        ? '${(job.progress * 100).round()}%'
        : converted != null
        ? '${job.stateLabel} ${(converted * 100).round()}%'
        : job.stateLabel;
    final detail = switch (job.state) {
      'failed' => job.error,
      'queued' || 'converting' => '',
      _ when job.total > 0 =>
        '${formatBytes(job.bytes)} / ${formatBytes(job.total)}',
      _ when job.bytes > 0 => formatBytes(job.bytes),
      _ => '',
    };
    final secondary = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    final title = '${job.drama.title} 第 ${job.episode.number} 集';
    return Semantics(
      label: '$title，$state${detail.isEmpty ? '' : '，$detail'}',
      checked: selected,
      child: FocusRing(
        radius: 16,
        child: Material(
          color: colors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: selected == true
                ? BorderSide(color: colors.primary, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: selected == null ? null : onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                spacing: 16,
                children: [
                  if (selected case final selected?)
                    Checkbox(value: selected, onChanged: (_) => onToggle()),
                  SizedBox(
                    width: 48,
                    height: 72,
                    child: DramaCover(
                      drama: job.drama,
                      radius: 8,
                      details: false,
                    ),
                  ),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 6,
                        children: [
                          Row(
                            spacing: 8,
                            children: [
                              Flexible(
                                child: Text(
                                  job.drama.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '第 ${job.episode.number} 集',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              SourceTag(job.drama.source),
                            ],
                          ),
                          LinearProgressIndicator(
                            value: job.converting ? converted : job.progress,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            color: downloading || job.converting
                                ? null
                                : colors.outline,
                          ),
                          Row(
                            spacing: 12,
                            children: [
                              Text(
                                state,
                                style: secondary.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: failed
                                      ? colors.error
                                      : downloading || job.converting
                                      ? colors.primary
                                      : null,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: secondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selected == null && !job.converting)
                    FocusRing(
                      radius: 20,
                      child: IconButton.filledTonal(
                        tooltip: failed
                            ? '重试'
                            : job.active
                            ? '暂停'
                            : '继续',
                        onPressed: busy ? null : onControl,
                        icon: Icon(
                          failed
                              ? Icons.refresh_rounded
                              : job.active
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
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
