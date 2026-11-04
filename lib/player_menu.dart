import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'episode_browser.dart';
import 'playback_preferences.dart';
import 'video_enhancement.dart';
import 'video_enhancement_settings.dart';
import 'diary_service.dart';

enum PlayerMenuSection { episodes, speed, quality, fit, settings }

class PlayerMenu extends StatefulWidget {
  const PlayerMenu({
    super.key,
    required this.section,
    required this.episodes,
    required this.currentIndex,
    required this.preferences,
    required this.qualities,
    required this.actualQuality,
    required this.local,
    required this.favorite,
    required this.mobile,
    required this.onEpisode,
    required this.onPreferences,
    required this.onFavorite,
    this.showDanmaku = false,
    this.danmakuStatus = '',
    this.onRetryDanmaku,
    this.preloadStatus = '',
    this.enhancement,
    this.onCompareEnhancement,
  });

  final PlayerMenuSection section;
  final List<Episode> episodes;
  final int currentIndex;
  final PlaybackPreferences preferences;
  final List<int> qualities;
  final int actualQuality;
  final bool local;
  final bool favorite;
  final bool mobile;
  final bool showDanmaku;
  final String danmakuStatus;
  final VoidCallback? onRetryDanmaku;
  final String preloadStatus;
  final VideoEnhancementController? enhancement;
  final VoidCallback? onCompareEnhancement;
  final ValueChanged<int> onEpisode;
  final Future<void> Function(PlaybackPreferences) onPreferences;
  final Future<void> Function() onFavorite;

  @override
  State<PlayerMenu> createState() => _PlayerMenuState();
}

class _PlayerMenuState extends State<PlayerMenu> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '未能保存设置，请检查存储空间后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final colors = Theme.of(context).colorScheme;
    final title = switch (widget.section) {
      PlayerMenuSection.episodes => '选集 · 共 ${widget.episodes.length} 集',
      PlayerMenuSection.speed => '播放倍速',
      PlayerMenuSection.quality => '清晰度',
      PlayerMenuSection.fit => '画面比例',
      PlayerMenuSection.settings => '播放设置',
    };
    return Dialog(
      key: const ValueKey('player-menu'),
      alignment: landscape ? Alignment.centerRight : Alignment.bottomCenter,
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: colors.surface,
      child: SizedBox(
        width: landscape ? math.min(440, size.width * .6) : 600,
        height: landscape ? size.height : size.height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭菜单',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFFB4A8)),
                ),
              ),
            Expanded(
              child: widget.section == PlayerMenuSection.episodes
                  ? PlayerEpisodeGrid(
                      episodes: widget.episodes,
                      currentIndex: widget.currentIndex,
                      keyPrefix: 'menu-episode',
                      onSelected: widget.onEpisode,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                      child: _settings(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settings() {
    final preferences = widget.preferences;
    final all = widget.section == PlayerMenuSection.settings;
    final colors = Theme.of(context).colorScheme;
    final helperStyle = TextStyle(
      fontSize: 13,
      color: colors.onSurfaceVariant,
      height: 1.5,
    );
    final qualities = {
      0,
      ...widget.qualities.where((quality) => quality > 0),
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (all || widget.section == PlayerMenuSection.speed) ...[
          const Text('倍速'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final speed in playbackSpeeds)
                ChoiceChip(
                  key: ValueKey('menu-speed-$speed'),
                  label: Text('${speed}x'),
                  selected: speed == preferences.speed,
                  onSelected: _busy
                      ? null
                      : (_) => _run(
                          () => widget.onPreferences(
                            preferences.copyWith(speed: speed),
                          ),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (all || widget.section == PlayerMenuSection.quality) ...[
          const Text('清晰度'),
          const SizedBox(height: 8),
          Text(
            widget.local
                ? '本集正在播放本地原画，画质偏好用于后续在线播放。'
                : widget.actualQuality > 0
                ? '当前播放 ${widget.actualQuality}P'
                : '使用源站可用画质',
            style: helperStyle,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final quality in qualities)
                ChoiceChip(
                  key: ValueKey('menu-quality-$quality'),
                  label: Text(quality == 0 ? '自动（优先高清）' : '${quality}P'),
                  selected: quality == preferences.quality,
                  onSelected: _busy
                      ? null
                      : (_) => _run(
                          () => widget.onPreferences(
                            preferences.copyWith(quality: quality),
                          ),
                        ),
                ),
            ],
          ),
          if (!qualities.contains(preferences.quality))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已保存 ${preferences.quality}P 偏好，本集暂无此画质。',
                style: helperStyle,
              ),
            ),
          const SizedBox(height: 20),
        ],
        if ((all || widget.section == PlayerMenuSection.quality) &&
            widget.enhancement != null)
          VideoEnhancementSettings(
            controller: widget.enhancement!,
            busy: _busy,
            onChanged: (enhancement) => _run(
              () => widget.onPreferences(
                preferences.copyWith(enhancement: enhancement),
              ),
            ),
            onCompare: widget.onCompareEnhancement ?? () {},
          ),
        if (all && widget.showDanmaku) ...[
          SwitchListTile.adaptive(
            key: const ValueKey('player-danmaku-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('弹幕'),
            subtitle: Text(widget.danmakuStatus),
            value: preferences.danmaku,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(danmaku: value),
                    ),
                  ),
          ),
          if (widget.onRetryDanmaku != null)
            TextButton.icon(
              key: const ValueKey('player-danmaku-retry'),
              onPressed: _busy ? null : widget.onRetryDanmaku,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试弹幕'),
            ),
          const SizedBox(height: 8),
        ],
        if (all || widget.section == PlayerMenuSection.fit) ...[
          const Text('画面比例'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in fitTypeEntries)
                ChoiceChip(
                  key: ValueKey('menu-fit-${entry.key}'),
                  label: Text(entry.label),
                  selected: entry.key == preferences.fitType,
                  onSelected: _busy
                      ? null
                      : (_) => _run(
                          () => widget.onPreferences(
                            preferences.copyWith(fitType: entry.key),
                          ),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (all) ...[
          SwitchListTile.adaptive(
            key: const ValueKey('player-slide-volume-brightness'),
            contentPadding: EdgeInsets.zero,
            title: const Text('滑动调节音量与亮度'),
            subtitle: const Text('左侧上下滑调亮度，右侧上下滑调音量'),
            value: preferences.slideVolumeBrightness,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(slideVolumeBrightness: value),
                    ),
                  ),
          ),
          SwitchListTile.adaptive(
            key: const ValueKey('player-slide-fullscreen'),
            contentPadding: EdgeInsets.zero,
            title: const Text('中部滑动切换全屏'),
            subtitle: const Text('播放器中三分之一区域上下滑动进入或退出全屏'),
            value: preferences.slideFullscreen,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(slideFullscreen: value),
                    ),
                  ),
          ),
          SwitchListTile.adaptive(
            key: const ValueKey('player-quick-double-tap'),
            contentPadding: EdgeInsets.zero,
            title: const Text('双击快进快退'),
            subtitle: const Text('开启后双击左 / 右区域快退 / 快进；关闭后双击任意位置播放暂停'),
            value: preferences.quickDoubleTap,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(quickDoubleTap: value),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('快进快退步长'),
                for (final seconds in const [5, 10, 15, 30])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('menu-double-tap-$seconds'),
                      label: Text('$seconds 秒'),
                      selected: seconds == preferences.doubleTapSeekSeconds,
                      onSelected: _busy
                          ? null
                          : (_) => _run(
                              () => widget.onPreferences(
                                preferences.copyWith(
                                  doubleTapSeekSeconds: seconds,
                                ),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('横滑进度幅度'),
                for (final seconds in dragSeekSteps)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('menu-drag-seek-$seconds'),
                      label: Text('$seconds 秒'),
                      selected: seconds == preferences.dragSeekSeconds,
                      onSelected: _busy
                          ? null
                          : (_) => _run(
                              () => widget.onPreferences(
                                preferences.copyWith(
                                  dragSeekSeconds: seconds,
                                ),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('长按倍速'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final speed in const [2.0, 2.5, 3.0, 4.0])
                ChoiceChip(
                  key: ValueKey('menu-long-press-speed-$speed'),
                  label: Text('${speed}x'),
                  selected: speed == preferences.longPressSpeed,
                  onSelected: _busy
                      ? null
                      : (_) => _run(
                          () => widget.onPreferences(
                            preferences.copyWith(longPressSpeed: speed),
                          ),
                        ),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            key: const ValueKey('player-auto-long-press-speed'),
            contentPadding: EdgeInsets.zero,
            title: const Text('长按使用动态倍速'),
            subtitle: const Text('开启后长按倍速为当前播放速度的 2 倍'),
            value: preferences.autoLongPressSpeed,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(autoLongPressSpeed: value),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
        ],
        if (all) ...[
          SwitchListTile.adaptive(
            key: const ValueKey('player-preload-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('下一集预加载'),
            subtitle: Text(widget.local ? '本地播放不预取网络视频' : widget.preloadStatus),
            value: preferences.preload,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(preload: value),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey('player-auto-advance'),
            contentPadding: EdgeInsets.zero,
            title: const Text('自动连播'),
            subtitle: const Text('关闭后，播放结束停在当前集'),
            value: preferences.autoAdvance,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(autoAdvance: value),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('player-favorite'),
            onPressed: _busy ? null : () => _run(widget.onFavorite),
            icon: Icon(
              widget.favorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
            ),
            label: Text(widget.favorite ? '取消追剧' : '加入追剧'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('player-diary-btn'),
            onPressed: () => DiaryService.showDiaryDialog(context),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('查看播放调试日记'),
          ),
          const SizedBox(height: 20),
          Text(
            widget.mobile
                ? '左侧上下滑调亮度，右侧上下滑调音量，中部上滑进入全屏、下滑退出全屏；左右滑动拖进度（一屏约 ${preferences.dragSeekSeconds} 秒），滑到顶部角落松开取消；双击快进快退关闭时，双击任意位置播放暂停；长按临时倍速，倍速中上滑锁定、下滑解锁。'
                : '空格：播放 / 暂停\n左右键：后退 / 快进 5 秒\n长按右键或画面：临时倍速\n上下键：音量 ±5%，M：静音\nF、F11、Ctrl+F：全屏\nEsc：先关闭菜单，再退出全屏',
            style: helperStyle.copyWith(height: 1.6),
          ),
        ],
      ],
    );
  }
}

class PlayerEpisodeGrid extends StatelessWidget {
  const PlayerEpisodeGrid({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onSelected,
    this.keyPrefix = 'play-episode',
    this.compact = false,
    this.title = '选集',
  });
  final List<Episode> episodes;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  final bool compact;
  final String title;
  @override
  Widget build(BuildContext context) => EpisodeBrowser(
    episodes: episodes,
    currentNumber: episodes.isEmpty
        ? null
        : episodes[currentIndex.clamp(0, episodes.length - 1)].number,
    onSelected: onSelected,
    keyPrefix: keyPrefix,
    compact: compact,
    title: title,
  );
}
