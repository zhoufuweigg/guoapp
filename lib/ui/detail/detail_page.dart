import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../drama_details.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../downloads/download_picker_page.dart';
import '../player/playback_handle.dart';
import '../player/playback_page.dart';
import '../shell/app_shell.dart';
import '../widgets/cover_backdrop.dart';
import '../widgets/cover_image.dart';
import '../widgets/focus_ring.dart';
import '../widgets/follow_button.dart';
import '../widgets/status_view.dart';

class _Metrics {
  const _Metrics({
    required this.cover,
    required this.coverRadius,
    required this.title,
    required this.meta,
    required this.tag,
    required this.note,
    required this.body,
    required this.bodyHeight,
    required this.button,
    required this.buttonText,
    required this.buttonIcon,
    required this.section,
    required this.summary,
    required this.chip,
    required this.chipRadius,
    required this.chipText,
    required this.chipPadding,
    required this.cell,
    required this.cellRadius,
    required this.cellText,
    required this.cellGap,
    this.columns = 0,
    this.cellWidth = 0,
    this.vipBadge = false,
    this.follow = 40,
  });
  final Size cover;
  final double coverRadius;
  final double title;
  final double meta;
  final double tag;
  final double note;
  final double body;
  final double bodyHeight;
  final double button;
  final double buttonText;
  final double buttonIcon;
  final double section;
  final double summary;
  final double chip;
  final double chipRadius;
  final double chipText;
  final double chipPadding;
  final double cell;
  final double cellRadius;
  final double cellText;
  final double cellGap;
  final int columns;
  final double cellWidth;
  final bool vipBadge;
  final double follow;

  int columnsFor(double width) => columns > 0
      ? columns
      : math.max(4, ((width + cellGap) / (cellWidth + cellGap)).floor());
}

const _phone = _Metrics(
  cover: Size(120, 180),
  coverRadius: 12,
  title: 22,
  meta: 13,
  tag: 12,
  note: 12,
  body: 14,
  bodyHeight: 1.6,
  button: 52,
  buttonText: 16,
  buttonIcon: 24,
  section: 17,
  summary: 13,
  chip: 32,
  chipRadius: 8,
  chipText: 13,
  chipPadding: 14,
  cell: 54,
  cellRadius: 12,
  cellText: 16,
  cellGap: 10,
  columns: 5,
);

const _desktop = _Metrics(
  cover: Size(160, 240),
  coverRadius: 14,
  title: 28,
  meta: 14,
  tag: 12,
  note: 13,
  body: 14,
  bodyHeight: 1.7,
  button: 48,
  buttonText: 15,
  buttonIcon: 22,
  section: 18,
  summary: 13,
  chip: 32,
  chipRadius: 8,
  chipText: 13,
  chipPadding: 14,
  cell: 52,
  cellRadius: 12,
  cellText: 16,
  cellGap: 10,
  cellWidth: 72,
);

const _pad = _Metrics(
  cover: Size(150, 225),
  coverRadius: 14,
  title: 24,
  meta: 14,
  tag: 13,
  note: 13,
  body: 15,
  bodyHeight: 1.6,
  button: 56,
  buttonText: 16,
  buttonIcon: 24,
  section: 18,
  summary: 13,
  chip: 40,
  chipRadius: 10,
  chipText: 14,
  chipPadding: 16,
  cell: 56,
  cellRadius: 12,
  cellText: 17,
  cellGap: 12,
  cellWidth: 76,
  follow: 44,
);

const _television = _Metrics(
  cover: Size(140, 210),
  coverRadius: 12,
  title: 28,
  meta: 16,
  tag: 14,
  note: 15,
  body: 15,
  bodyHeight: 1.65,
  button: 52,
  buttonText: 18,
  buttonIcon: 24,
  section: 20,
  summary: 15,
  chip: 40,
  chipRadius: 12,
  chipText: 16,
  chipPadding: 18,
  cell: 60,
  cellRadius: 12,
  cellText: 20,
  cellGap: 12,
  columns: 6,
  vipBadge: true,
  follow: 52,
);

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.store, required this.drama});
  final LocalStore store;
  final Drama drama;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  DramaDetails? _details;
  PlaybackHandle? _handle;
  bool _watching = false;
  final _currentEpisode = GlobalKey();
  bool _expanded = false;
  final _playFocus = FocusNode();
  final _followFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _groupFocus = <FocusNode>[];
  final _episodeFocus = List.generate(episodeGroupSize, (_) => FocusNode());
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _details ??= DramaDetails(
      AppScope.of(context).repository,
      widget.store,
      widget.drama,
    )..addListener(_preopen);
  }

  @override
  void dispose() {
    _handle?.dispose();
    _details?.dispose();
    for (final node in [
      _playFocus,
      _followFocus,
      _descriptionFocus,
      ..._groupFocus,
      ..._episodeFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  bool get _canDownload =>
      AppScope.of(context).repository.supportsDownloads &&
      widget.store.canDownload;

  bool get _ready => !_details!.loading && _details!.episodes.isNotEmpty;

  Future<void> _refresh() async {
    final details = _details!;
    await details.load();
    if (!mounted || details.error == null || details.episodes.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(details.error!)));
  }

  double _startAt(int index, {required bool resume}) {
    final watch = _details!.watch;
    return resume &&
            watch?.episode == _details!.episodes[index].number &&
            !watch!.finished
        ? watch.position
        : 0.0;
  }

  DramaDetail get _detail {
    final details = _details!;
    return DramaDetail(
      details.drama,
      details.episodes,
      warning: details.warning,
    );
  }

  PlaybackHandle _open(
    int index, {
    required double position,
    bool autoplay = true,
  }) => PlaybackHandle(
    repository: AppScope.of(context).repository,
    store: widget.store,
    detail: _detail,
    index: index,
    position: position,
    autoplay: autoplay,
    preopen: widget.store.playbackPreferences.preopens(
      television: AppScope.of(context).television,
    ),
  );

  void _preopen() {
    final details = _details!;
    if (_handle != null ||
        _watching ||
        !mounted ||
        !_ready ||
        !details.allowed) {
      return;
    }
    final index = details.resumeIndex;
    _handle = _open(
      index,
      position: _startAt(index, resume: true),
      autoplay: false,
    );
  }

  Future<void> _play(int index, {bool resume = false}) async {
    final details = _details!;
    final episode = details.episodes[index];
    if (episode.vip &&
        details.drama.source != SourceSite.dsd.id &&
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('这是一集 VIP 内容'),
                content: const Text('站源可能只提供试看或限制播放。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('尝试播放'),
                  ),
                ],
              ),
            ) !=
            true) {
      return;
    }
    if (!mounted || !details.allowed) return;
    final position = _startAt(index, resume: resume);
    final handle = _handle ?? _open(index, position: position);
    _handle = null;
    handle.session.start(index, position: position);
    _watching = true;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaybackPage(store: widget.store, handle: handle),
      ),
    );
    _watching = false;
    if (mounted && AppScope.of(context).television) _focusWatched(details);
  }

  void _focusWatched(DramaDetails details) {
    final index = details.currentIndex;
    if (index == null) return;
    details.selectGroup(index ~/ episodeGroupSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _episodeFocus[index % episodeGroupSize].requestFocus();
    });
  }

  void _download() => openPage<void>(
    context,
    (_) => DownloadPickerPage(store: widget.store, detail: _detail),
  );

  void _locate(int index) {
    _details!.selectGroup(index ~/ episodeGroupSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _currentEpisode.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.3,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _details!,
    builder: (context, _) {
      final details = _details!;
      if (!details.allowed) {
        return Scaffold(
          appBar: AppBar(),
          body: const StatusView(
            title: '当前用户无权访问',
            message: '请返回剧库后重新选择。',
            icon: Icons.lock_outline_rounded,
          ),
        );
      }
      final form = AppScope.formFactorOf(context);
      if (form == FormFactor.television) return _televisionPage(details);
      if (form == FormFactor.phone || MediaQuery.sizeOf(context).width < 840) {
        return _phonePage(details);
      }
      return _widePage(details, desktop: form == FormFactor.window);
    },
  );

  PreferredSizeWidget _appBar(DramaDetails details, double height) {
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      toolbarHeight: height,
      backgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.scrolledUnder)
            ? colors.surfaceContainer
            : Colors.transparent,
      ),
      actions: [
        IconButton(
          tooltip: '更新剧集信息',
          onPressed: details.loading ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _withBackdrop(Drama drama, double height, Widget child) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: height,
          child: CoverBackdrop(
            drama: drama,
            sigma: 36,
            opacity: theme.brightness == Brightness.dark ? 0.55 : 0.45,
            overlay: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.92],
              colors: [surface.withValues(alpha: 0), surface],
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _phonePage(DramaDetails details) {
    const m = _phone;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final drama = details.drama;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _appBar(details, kToolbarHeight),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _withBackdrop(
              drama,
              top + 250,
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 16,
                      children: [
                        _cover(drama, m),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _followingHeadline(details, m, 6),
                          ),
                        ),
                      ],
                    ),
                    if (_stats(drama, m) case final stats?)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: stats,
                      ),
                    if (_tags(drama, m) case final tags?)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: tags,
                      ),
                    if (drama.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _description(drama, m),
                      ),
                    if (details.warning.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _warning(details.warning, m),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (details.episodes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _episodeStatus(details),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: _episodeHeader(details, m),
              ),
            ),
            if (details.groupCount > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: m.chip + 2,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                    itemCount: details.groupCount,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, group) =>
                        _groupChip(details, m, group),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverToBoxAdapter(child: _grid(details, m)),
            ),
          ],
        ],
      ),
      bottomNavigationBar: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              spacing: 12,
              children: [
                if (_canDownload)
                  FocusRing(
                    radius: m.button / 2,
                    child: IconButton.filledTonal(
                      tooltip: '下载选集',
                      onPressed: _ready ? _download : null,
                      style: IconButton.styleFrom(
                        minimumSize: Size.square(m.button),
                      ),
                      icon: const Icon(Icons.download_rounded),
                    ),
                  ),
                Expanded(child: _playButton(details, m)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _widePage(DramaDetails details, {required bool desktop}) {
    final m = desktop ? _desktop : _pad;
    final top = MediaQuery.paddingOf(context).top + 64;
    final inset = desktop ? 32.0 : 24.0;
    final gap = desktop ? 40.0 : 32.0;
    final side = desktop ? 420.0 : 380.0;
    final drama = details.drama;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: desktop ? 20 : 18,
          children: [
            _cover(drama, m),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _followingHeadline(details, m, 4),
              ),
            ),
          ],
        ),
        if (_stats(drama, m) case final stats?)
          Padding(
            padding: EdgeInsets.only(top: desktop ? 18 : 16),
            child: stats,
          ),
        if (_tags(drama, m) case final tags?)
          Padding(padding: const EdgeInsets.only(top: 10), child: tags),
        Padding(
          padding: EdgeInsets.only(top: desktop ? 22 : 20),
          child: Row(
            spacing: 12,
            children: [
              Expanded(child: _playButton(details, m)),
              if (_canDownload) _downloadButton(m),
            ],
          ),
        ),
        if (drama.description.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: desktop ? 22 : 20),
            child: _description(drama, m),
          ),
        if (details.warning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _warning(details.warning, m),
          ),
      ],
    );
    final episodes = details.episodes.isEmpty
        ? SizedBox(height: 320, child: _episodeStatus(details))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: desktop ? 44 : 48,
                child: _episodeHeader(details, m),
              ),
              if (details.groupCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var group = 0; group < details.groupCount; group++)
                        _groupChip(details, m, group),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _grid(details, m),
              ),
            ],
          );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _appBar(details, 64),
      body: SingleChildScrollView(
        child: _withBackdrop(
          drama,
          top + 336,
          Padding(
            padding: EdgeInsets.fromLTRB(inset, top + 4, inset, 40),
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= side + gap + 480
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: gap,
                      children: [
                        SizedBox(width: side, child: info),
                        Expanded(child: episodes),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: gap,
                      children: [info, episodes],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _televisionPage(DramaDetails details) {
    const m = _television;
    if (_ready && !_entered) {
      _entered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocus.requestFocus();
      });
    }
    while (_groupFocus.length < details.groupCount) {
      _groupFocus.add(FocusNode());
    }
    final page = Scaffold(
      body: _withBackdrop(
        details.drama,
        340,
        Padding(
          padding: const EdgeInsets.fromLTRB(
            televisionInset,
            40,
            televisionInset,
            27,
          ),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) => _televisionKey(details, m, event),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 40,
              children: [
                SizedBox(width: 380, child: _televisionInfo(details, m)),
                Expanded(child: _televisionEpisodes(details, m)),
              ],
            ),
          ),
        ),
      ),
    );
    return ListenableBuilder(
      listenable: _playFocus,
      builder: (context, child) => PopScope(
        canPop: !_ready || _playFocus.hasFocus,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _playFocus.requestFocus();
        },
        child: child!,
      ),
      child: page,
    );
  }

  KeyEventResult _televisionKey(
    DramaDetails details,
    _Metrics m,
    KeyEvent event,
  ) {
    final node = FocusManager.instance.primaryFocus;
    final key = event.logicalKey;
    if (event is KeyUpEvent ||
        node == null ||
        !{
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        }.contains(key)) {
      return KeyEventResult.ignored;
    }
    final group = _groupFocus.indexOf(node);
    final episode = _episodeFocus.indexOf(node);
    if (node == _playFocus ||
        node == _followFocus ||
        node == _descriptionFocus) {
      if (key == LogicalKeyboardKey.arrowRight && node == _playFocus) {
        _followFocus.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _focusEpisodes(details);
      } else if (key == LogicalKeyboardKey.arrowLeft && node == _followFocus) {
        _playFocus.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowDown &&
          node != _descriptionFocus &&
          _descriptionFocus.context != null) {
        _descriptionFocus.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowUp &&
          node == _descriptionFocus) {
        _playFocus.requestFocus();
      }
    } else if (group >= 0) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        group == 0
            ? _playFocus.requestFocus()
            : _focusGroup(details, group - 1);
      } else if (key == LogicalKeyboardKey.arrowRight &&
          group + 1 < details.groupCount) {
        _focusGroup(details, group + 1);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _focusEpisodes(details);
      }
    } else if (episode >= 0) {
      final columns = m.columns;
      final count = details.groupEpisodes.length;
      final column = episode % columns;
      final target = switch (key) {
        LogicalKeyboardKey.arrowLeft when column == 0 => null,
        LogicalKeyboardKey.arrowLeft => episode - 1,
        LogicalKeyboardKey.arrowRight
            when column < columns - 1 && episode + 1 < count =>
          episode + 1,
        LogicalKeyboardKey.arrowUp when episode >= columns => episode - columns,
        LogicalKeyboardKey.arrowDown
            when episode ~/ columns < (count - 1) ~/ columns =>
          math.min(episode + columns, count - 1),
        _ => episode,
      };
      if (target == null) {
        _playFocus.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowUp &&
          episode < columns &&
          details.groupCount > 1) {
        revealFocus(_groupFocus[details.group]);
      } else {
        _episodeFocus[target].requestFocus();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _focusGroup(DramaDetails details, int group) {
    details.selectGroup(group);
    revealFocus(_groupFocus[group]);
  }

  void _focusEpisodes(DramaDetails details) {
    final count = details.groupEpisodes.length;
    if (count == 0) return;
    final start = details.group * episodeGroupSize;
    final offset = (details.currentIndex ?? -1) - start;
    _episodeFocus[offset >= 0 && offset < count ? offset : 0].requestFocus();
  }

  Widget _televisionInfo(DramaDetails details, _Metrics m) {
    final drama = details.drama;
    final colors = Theme.of(context).colorScheme;
    final sub = TextStyle(
      fontSize: m.note,
      height: 1.4,
      color: colors.onSurfaceVariant,
    );
    final meta = [
      SourceSite.byId(drama.source).name,
      if (drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown')
        drama.releaseLabel,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 20,
          children: [
            _cover(drama, m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      drama.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: m.title,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                  Text(
                    meta.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sub.copyWith(fontSize: m.meta),
                  ),
                  if (drama.category.isNotEmpty)
                    Text(
                      drama.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sub,
                    ),
                  if (drama.onlineDate.isNotEmpty)
                    Text('${drama.onlineDate} 上线', style: sub),
                  if (drama.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        height: 28,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          clipBehavior: Clip.hardEdge,
                          children: [
                            for (final tag in drama.tags.take(12))
                              Container(
                                height: 28,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    tag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: m.tag),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(
            spacing: 12,
            children: [
              Expanded(child: _playButton(details, m, focusNode: _playFocus)),
              FollowPill(
                store: widget.store,
                drama: drama,
                height: m.follow,
                focusNode: _followFocus,
              ),
            ],
          ),
        ),
        if (drama.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: _televisionDescription(drama, m),
          ),
      ],
    );
  }

  Widget _televisionDescription(Drama drama, _Metrics m) {
    final colors = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: m.body,
      height: m.bodyHeight,
      color: colors.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            drama.description,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          if (_exceeds(drama.description, style, 4, constraints.maxWidth))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FocusRing(
                radius: 18,
                child: FilledButton(
                  focusNode: _descriptionFocus,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _DescriptionDialog(drama: drama),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.surfaceContainerHighest,
                    foregroundColor: colors.onSurface,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('展开简介'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _televisionEpisodes(DramaDetails details, _Metrics m) {
    if (details.episodes.isEmpty) {
      return _episodeStatus(details, autofocus: true);
    }
    final grouped = details.groupCount > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _episodeTitle(details, m, prefix: '共 '),
          ),
        ),
        if (grouped)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Transform.translate(
              offset: const Offset(-4, 0),
              child: SizedBox(
                height: m.chip + 8,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    spacing: 12,
                    children: [
                      for (var group = 0; group < details.groupCount; group++)
                        _groupChip(
                          details,
                          m,
                          group,
                          focusNode: _groupFocus[group],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: grouped ? 14 : 18),
          child: _grid(details, m, focus: _episodeFocus),
        ),
      ],
    );
  }

  Widget _cover(Drama drama, _Metrics m) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(m.coverRadius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x4D000000),
          blurRadius: 26,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: SizedBox.fromSize(
      size: m.cover,
      child: DramaCover(drama: drama, radius: m.coverRadius),
    ),
  );

  Widget _headline(
    DramaDetails details,
    _Metrics m, {
    double spacing = 8,
    List<Widget> trailing = const [],
  }) {
    final drama = details.drama;
    TextStyle sub(double size) => TextStyle(
      fontSize: size,
      height: 1.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final meta = [
      SourceSite.byId(drama.source).name,
      if (drama.episodes > 0) '共 ${drama.episodes} 集',
      if (drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown')
        drama.releaseLabel,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: spacing,
      children: [
        Text(
          drama.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: m.title,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        Text(meta.join(' · '), style: sub(m.meta)),
        if (drama.category.isNotEmpty) Text(drama.category, style: sub(m.meta)),
        if (drama.source == 'huangdou')
          Text(
            drama.vipStatus == null
                ? 'VIP 状态待补齐'
                : drama.vip
                ? 'VIP 内容'
                : '免费内容',
            style: sub(m.tag),
          ),
        ...trailing,
      ],
    );
  }

  Widget _followingHeadline(DramaDetails details, _Metrics m, double top) =>
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: m.cover.height - top),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headline(details, m),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FollowPill(
                  store: widget.store,
                  drama: details.drama,
                  height: m.follow,
                ),
              ),
            ],
          ),
        ),
      );

  Widget? _stats(Drama drama, _Metrics m) {
    final stats = [
      if (drama.onlineDate.isNotEmpty) '${drama.onlineDate} 上线',
      if (drama.views.isNotEmpty) '播放 ${drama.views}',
    ];
    if (stats.isEmpty) return null;
    return Text(
      stats.join(' · '),
      style: TextStyle(
        fontSize: m.note,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget? _tags(Drama drama, _Metrics m) {
    if (drama.tags.isEmpty) return null;
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in drama.tags.take(12))
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text(tag, style: TextStyle(fontSize: m.tag)),
            ),
          ),
      ],
    );
  }

  Widget _description(Drama drama, _Metrics m) {
    final colors = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: m.body,
      height: m.bodyHeight,
      color: colors.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = _exceeds(
          drama.description,
          style,
          3,
          constraints.maxWidth,
        );
        final label = Text(_expanded ? '收起简介' : '展开简介');
        void toggle() => setState(() => _expanded = !_expanded);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              drama.description,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (overflows)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: toggle, child: label),
              ),
          ],
        );
      },
    );
  }

  bool _exceeds(String text, TextStyle style, int maxLines, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final exceeds = painter.didExceedMaxLines;
    painter.dispose();
    return exceeds;
  }

  Widget _warning(String text, _Metrics m) {
    final color = Theme.of(context).colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.error_outline_rounded,
            size: m.note + 3,
            color: color,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: m.note, height: 1.5, color: color),
          ),
        ),
      ],
    );
  }

  Widget _playButton(DramaDetails details, _Metrics m, {FocusNode? focusNode}) {
    final label = details.watch != null && details.episodes.isNotEmpty
        ? '继续播放 · 第 ${details.episodes[details.resumeIndex].number} 集'
        : '立即播放';
    return FocusRing(
      radius: m.button / 2,
      child: FilledButton.icon(
        key: const ValueKey('detail-play'),
        focusNode: focusNode,
        onPressed: _ready
            ? () => _play(details.resumeIndex, resume: true)
            : null,
        style: FilledButton.styleFrom(
          minimumSize: Size(0, m.button),
          iconSize: m.buttonIcon,
          textStyle: TextStyle(
            fontSize: m.buttonText,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _downloadButton(_Metrics m) => FocusRing(
    radius: m.button / 2,
    child: FilledButton.tonalIcon(
      onPressed: _ready ? _download : null,
      style: FilledButton.styleFrom(
        minimumSize: Size(0, m.button),
        iconSize: m.buttonIcon - 2,
        textStyle: TextStyle(
          fontSize: m.buttonText - 1,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: const Icon(Icons.download_rounded),
      label: const Text('下载选集'),
    ),
  );

  Widget _episodeStatus(DramaDetails details, {bool autofocus = false}) {
    if (details.loading) return const StatusView.loading();
    return StatusView(
      title: details.error != null ? '剧集信息暂时不可用' : '暂时没有可播放的集数',
      message: details.error ?? '可以更新剧集信息后重试。',
      icon: Icons.error_outline_rounded,
      action: '重试',
      onAction: details.load,
      autofocus: autofocus,
    );
  }

  Widget _episodeTitle(DramaDetails details, _Metrics m, {String prefix = ''}) {
    final current = details.currentIndex;
    final summary = [
      '$prefix${details.episodes.length} 集',
      if (current != null) '当前第 ${details.episodes[current].number} 集',
    ].join(' · ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '选集',
          style: TextStyle(fontSize: m.section, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text(
          summary,
          style: TextStyle(
            fontSize: m.summary,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _episodeHeader(DramaDetails details, _Metrics m) => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: _episodeTitle(details, m),
        ),
      ),
      if (details.currentIndex case final current?)
        TextButton(
          onPressed: () => _locate(current),
          child: const Text('定位当前'),
        ),
    ],
  );

  Widget _groupChip(
    DramaDetails details,
    _Metrics m,
    int group, {
    FocusNode? focusNode,
  }) => _GroupChip(
    label: details.groupLabel(group),
    selected: group == details.group,
    metrics: m,
    focusNode: focusNode,
    onPressed: () => details.selectGroup(group),
  );

  Widget _grid(
    DramaDetails details,
    _Metrics m, {
    List<FocusNode> focus = const [],
  }) {
    final extent = math.max(
      m.cell,
      MediaQuery.textScalerOf(context).scale(m.cellText) + 28,
    );
    final current = details.currentIndex;
    final start = details.group * episodeGroupSize;
    final episodes = details.groupEpisodes;
    Widget cell(int offset) {
      final index = start + offset;
      final episode = episodes[offset];
      return _EpisodeCell(
        key: index == current
            ? _currentEpisode
            : ValueKey('episode-${episode.number}'),
        episode: episode,
        metrics: m,
        focusNode: offset < focus.length ? focus[offset] : null,
        current: index == current,
        watched: current != null && index < current,
        onPressed: () => _play(index),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = m.columnsFor(constraints.maxWidth);
        return Column(
          spacing: m.cellGap,
          children: [
            for (var row = 0; row < episodes.length; row += columns)
              SizedBox(
                height: extent,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: m.cellGap,
                  children: [
                    for (var offset = row; offset < row + columns; offset++)
                      Expanded(
                        child: offset < episodes.length
                            ? cell(offset)
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    required this.metrics,
    required this.onPressed,
    this.focusNode,
  });
  final String label;
  final bool selected;
  final _Metrics metrics;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final m = metrics;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(m.chipRadius),
    );
    final padding = EdgeInsets.symmetric(horizontal: m.chipPadding);
    final size = Size(0, m.chip);
    return FocusRing(
      radius: m.chipRadius,
      child: selected
          ? FilledButton.tonal(
              focusNode: focusNode,
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                shape: shape,
                padding: padding,
                minimumSize: size,
                textStyle: TextStyle(
                  fontSize: m.chipText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              focusNode: focusNode,
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                shape: shape,
                padding: padding,
                minimumSize: size,
                foregroundColor: colors.onSurfaceVariant,
                side: BorderSide(color: colors.outlineVariant),
                textStyle: TextStyle(fontSize: m.chipText),
              ),
              child: Text(label),
            ),
    );
  }
}

class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    super.key,
    required this.episode,
    required this.metrics,
    required this.current,
    required this.watched,
    required this.onPressed,
    this.focusNode,
  });
  final Episode episode;
  final _Metrics metrics;
  final bool current;
  final bool watched;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(metrics.cellRadius);
    return FocusRing(
      radius: metrics.cellRadius,
      child: Semantics(
        button: true,
        label: '第 ${episode.number} 集${episode.vip ? '，VIP' : ''}',
        excludeSemantics: true,
        child: Material(
          color: current ? colors.primaryContainer : colors.surfaceContainer,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: focusNode,
            onTap: onPressed,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Text(
                    '${episode.number}',
                    style: TextStyle(
                      fontSize: metrics.cellText,
                      fontWeight: current
                          ? FontWeight.w800
                          : watched
                          ? FontWeight.w400
                          : FontWeight.w600,
                      color: current
                          ? colors.onPrimaryContainer
                          : watched
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                ),
                if (episode.vip && metrics.vipBadge)
                  const Positioned(
                    right: 0,
                    top: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFF2C14E),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(6),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        child: Text(
                          'VIP',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                            color: Color(0xFF3A2A00),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (episode.vip)
                  Positioned(
                    right: 5,
                    top: 4,
                    child: Text(
                      'VIP',
                      style: TextStyle(
                        fontSize: metrics.cellText - 7,
                        fontWeight: FontWeight.w800,
                        color: dark ? vipGold : const Color(0xFFB08200),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DescriptionDialog extends StatefulWidget {
  const _DescriptionDialog({required this.drama});
  final Drama drama;

  @override
  State<_DescriptionDialog> createState() => _DescriptionDialogState();
}

class _DescriptionDialogState extends State<_DescriptionDialog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -120.0,
      LogicalKeyboardKey.arrowDown => 120.0,
      _ => null,
    };
    if (event is KeyUpEvent || step == null) return KeyEventResult.ignored;
    if (_scroll.hasClients) {
      final position = _scroll.position;
      _scroll.animateTo(
        (position.pixels + step).clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) => _onKey(event),
    child: AlertDialog(
      title: Text(widget.drama.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          controller: _scroll,
          child: Text(
            widget.drama.description,
            style: const TextStyle(fontSize: 16, height: 1.7),
          ),
        ),
      ),
      actions: [
        FocusRing(
          radius: 20,
          child: TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ),
      ],
    ),
  );
}
