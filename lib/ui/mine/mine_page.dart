import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../download_converter.dart';
import '../../download_overview.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../detail/detail_page.dart';
import '../downloads/downloads_page.dart';
import '../history/history_page.dart';
import '../shell/app_shell.dart';
import '../settings/settings_page.dart';
import '../widgets/cover_image.dart';
import '../widgets/drama_tile.dart';
import '../widgets/focus_ring.dart';
import '../widgets/page_header.dart';
import '../widgets/group_card.dart';

String _size(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
    : '${(bytes / (1 << 20)).round()} MB';

class MinePage extends StatelessWidget {
  const MinePage({
    super.key,
    required this.store,
    required this.downloads,
    required this.converter,
    required this.entryFocus,
    required this.onExitUp,
  });
  final LocalStore store;
  final DownloadOverview downloads;
  final DownloadConverter converter;
  final FocusNode entryFocus;
  final VoidCallback onExitUp;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([store, downloads]),
        builder: (context, _) => switch (AppScope.formFactorOf(context)) {
          FormFactor.phone => _phone(context),
          FormFactor.pad || FormFactor.window => _wide(context),
          FormFactor.television => _television(context),
        },
      ),
    ),
  );

  void _openHistory(BuildContext context) =>
      openPage<void>(context, (_) => HistoryPage(store: store));

  void _openDownloads(BuildContext context) => openPage<void>(
    context,
    (_) =>
        DownloadsPage(store: store, downloads: downloads, converter: converter),
  );

  Widget _userCard(BuildContext context) =>
      _UserCard(store: store, onTap: () => openUsers(context, store));

  Widget _settings(BuildContext context) => _SettingsEntry(
    onTap: () => openPage<void>(context, (_) => SettingsPage(store: store)),
  );

  Widget _poster(
    BuildContext context,
    WatchEntry entry,
    double width, {
    FocusNode? focusNode,
  }) {
    final drama = entry.drama;
    final total = drama.episodes;
    return ProgressPoster(
      drama: drama,
      width: width,
      focusNode: focusNode,
      progress: total > 0 ? entry.episode / total : 0,
      caption: total > 0 && entry.episode >= total && entry.finished
          ? '已看完'
          : '看到第 ${entry.episode} 集',
      tag: SourceSite.byId(drama.source).name,
      onTap: () => openPage<void>(
        context,
        (_) => DetailPage(store: store, drama: drama),
      ),
    );
  }

  Widget _phone(BuildContext context) {
    const width = 100.0;
    final history = store.history.take(20).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PageHeader(title: '我的'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _userCard(context),
        ),
        SectionHeader(
          title: '最近观看',
          action: '全部',
          onAction: () => _openHistory(context),
        ),
        const SizedBox(height: 6),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _EmptyHistory(height: 150),
          )
        else
          SizedBox(
            height: ProgressPoster.extentFor(context, width),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _poster(context, history[index], width),
            ),
          ),
        if (store.canDownload) ...[
          SectionHeader(
            title: '下载',
            action: '全部',
            onAction: () => _openDownloads(context),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _DownloadCard(downloads: downloads),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _settings(context),
        ),
      ],
    );
  }

  Widget _wide(BuildContext context) {
    final desktop = AppScope.formFactorOf(context) == FormFactor.window;
    final side = desktop ? 360.0 : 340.0;
    final gap = desktop ? 32.0 : 28.0;
    const sectionPadding = EdgeInsets.fromLTRB(4, 12, 0, 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 48;
        final split = width >= side + gap + 400;
        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _userCard(context),
            if (store.canDownload) ...[
              SectionHeader(
                title: '下载',
                action: '全部',
                onAction: () => _openDownloads(context),
                padding: sectionPadding,
              ),
              const SizedBox(height: 6),
              _DownloadCard(downloads: downloads),
            ],
            const SizedBox(height: 16),
            _settings(context),
          ],
        );
        final recent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: '最近观看',
              action: '全部',
              onAction: () => _openHistory(context),
              padding: split ? const EdgeInsets.only(left: 4) : sectionPadding,
            ),
            const SizedBox(height: 10),
            _historyGrid(
              context,
              split ? width - side - gap : width,
              desktop: desktop,
            ),
          ],
        );
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const PageHeader(title: '我的'),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: split
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: gap,
                      children: [
                        SizedBox(width: side, child: summary),
                        Expanded(child: recent),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [summary, recent],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _television(BuildContext context) {
    const columns = 7;
    const gap = 20.0;
    const padding = EdgeInsets.fromLTRB(
      televisionInset,
      14,
      televisionInset,
      27,
    );
    final history = store.history;
    final recent = history.take(columns - 1).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final tile =
            (constraints.maxWidth - padding.horizontal - gap * (columns - 1)) /
            columns;
        final page = SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - padding.vertical,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: 22,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    Semantics(
                      header: true,
                      child: const Text(
                        '最近观看',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (recent.isEmpty)
                      const _EmptyHistory(height: 200)
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: gap,
                        children: [
                          for (final (index, entry) in recent.indexed)
                            _poster(
                              context,
                              entry,
                              tile,
                              focusNode: index == 0 ? entryFocus : null,
                            ),
                          SizedBox(
                            width: tile,
                            child: _AllHistoryTile(
                              count: history.length,
                              onTap: () => _openHistory(context),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Row(
                  spacing: 20,
                  children: [
                    Expanded(
                      child: _TelevisionEntry(
                        icon: Icons.person_rounded,
                        primary: true,
                        focusNode: recent.isEmpty ? entryFocus : null,
                        title: store.profile.name,
                        subtitle:
                            '${store.profile.admin ? '管理员' : '普通用户'} · 切换用户',
                        onTap: () => openUsers(context, store),
                      ),
                    ),
                    Expanded(
                      child: _TelevisionEntry(
                        icon: Icons.settings_outlined,
                        title: '设置',
                        subtitle: '外观、播放、站源与网络',
                        onTap: () => openPage<void>(
                          context,
                          (_) => SettingsPage(store: store),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is KeyUpEvent ||
                event.logicalKey != LogicalKeyboardKey.arrowUp) {
              return KeyEventResult.ignored;
            }
            final moved = FocusManager.instance.primaryFocus?.focusInDirection(
              TraversalDirection.up,
            );
            if (moved != true) onExitUp();
            return KeyEventResult.handled;
          },
          child: page,
        );
      },
    );
  }

  Widget _historyGrid(
    BuildContext context,
    double width, {
    required bool desktop,
  }) {
    final minimum = desktop ? 140.0 : 120.0;
    final columnGap = desktop ? 18.0 : 16.0;
    final rowGap = desktop ? 22.0 : 20.0;
    final columns = ((width + columnGap) / (minimum + columnGap)).floor().clamp(
      1,
      99,
    );
    final tile = (width - columnGap * (columns - 1)) / columns;
    final history = store.history.take(columns * 2).toList();
    if (history.isEmpty) return const _EmptyHistory(height: 240);
    return Column(
      spacing: rowGap,
      children: [
        for (var start = 0; start < history.length; start += columns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: columnGap,
            children: [
              for (var index = start; index < start + columns; index++)
                Expanded(
                  child: index < history.length
                      ? _poster(context, history[index], tile)
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.store, required this.onTap});
  final LocalStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = store.profile;
    return FocusRing(
      radius: 20,
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              spacing: 14,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 26,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${profile.admin ? '管理员' : '普通用户'} · 轻点切换用户',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.downloads});
  final DownloadOverview downloads;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final secondary = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    final current = downloads.current;
    final active = downloads.active;
    return Semantics(
      container: true,
      label: '下载概览',
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (current != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 60,
                      child: DramaCover(
                        drama: current.drama,
                        radius: 8,
                        details: false,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 6,
                        children: [
                          Row(
                            spacing: 8,
                            children: [
                              Expanded(
                                child: Text(
                                  '${current.drama.title} · 第 ${current.episode.number} 集',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${(current.progress * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          LinearProgressIndicator(
                            value: current.progress,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          Text(
                            active > 1
                                ? '另有 ${active - 1} 个任务排队中'
                                : current.stateLabel,
                            style: secondary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    Icons.download_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Text(
                      downloads.completed == 0 && active == 0
                          ? '还没有下载任务'
                          : '已完成 ${downloads.completed} 集 · 占用 ${_size(downloads.completedBytes)}',
                      style: secondary.copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FocusRing(
      radius: 20,
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 14,
                children: [
                  Icon(
                    Icons.settings_outlined,
                    size: 22,
                    color: colors.onSurfaceVariant,
                  ),
                  const Expanded(
                    child: Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
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

class _AllHistoryTile extends StatelessWidget {
  const _AllHistoryTile({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FocusRing(
      radius: 12,
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '全部',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count 部',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
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

class _TelevisionEntry extends StatelessWidget {
  const _TelevisionEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
    this.focusNode,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FocusRing(
      radius: 20,
      scale: 1,
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: focusNode,
          focusColor: Colors.transparent,
          onTap: onTap,
          child: SizedBox(
            height: 84,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                spacing: 16,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: primary
                          ? colors.primaryContainer
                          : colors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: primary ? 26 : 24,
                      color: primary
                          ? colors.onPrimaryContainer
                          : colors.onSecondaryContainer,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 2,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          Icon(Icons.history_rounded, size: 32, color: colors.onSurfaceVariant),
          Text(
            '还没有观看记录',
            style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
