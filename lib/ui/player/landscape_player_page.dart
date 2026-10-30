import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app_device.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../../playback_preferences.dart';
import '../../playback_session.dart';
import '../app_scope.dart';
import '../downloads/download_actions.dart';
import '../theme/app_theme.dart';
import 'danmaku_overlay.dart';
import '../widgets/status_view.dart';
import '../widgets/follow_button.dart';
import 'episode_grid.dart';
import 'mini_player.dart';
import 'playback_handle.dart';
import 'playback_sheets.dart';
import 'player_surface.dart';
import 'swipe_controls.dart';
import 'window_fullscreen.dart';

enum _Panel { episodes, settings, speed, quality }

class LandscapePlayerPage extends StatefulWidget {
  const LandscapePlayerPage({
    super.key,
    required this.store,
    required this.handle,
    this.onFullscreen,
    this.onMiniWindow,
  });
  final LocalStore store;
  final PlaybackHandle handle;
  final VoidCallback? onFullscreen;
  final VoidCallback? onMiniWindow;

  @override
  State<LandscapePlayerPage> createState() => _LandscapePlayerPageState();
}

class _LandscapePlayerPageState extends State<LandscapePlayerPage>
    with WidgetsBindingObserver {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _selected = <int>{};
  final _links = {_Panel.speed: LayerLink(), _Panel.quality: LayerLink()};
  Player? _bound;
  Timer? _hideTimer;
  Timer? _tapTimer;
  Timer? _streakTimer;
  Timer? _clockTimer;
  Timer? _seekTimer;
  bool? _full;
  bool _visible = true;
  bool _selecting = false;
  bool _holding = false;
  bool _dragging = false;
  double? _seekValue;
  double? _seekTarget;
  int _streak = 0;
  int _streakTaps = 0;
  int _tab = 1;
  _Panel? _panel;
  DateTime _now = DateTime.now();
  ({int level, bool charging})? _battery;

  PlaybackSession get _session => widget.handle.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.onFullscreen == null) {
      unawaited(AppDevice.setPlayerOrientation(PlayerOrientation.auto));
    }
    _session.addListener(_bind);
    _bind();
    _scheduleHide();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final full = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (full == _full) return;
    _full = full;
    _panel = null;
    _visible = true;
    _scheduleHide();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ).catchError((Object _) {}),
    );
    _clockTimer?.cancel();
    _clockTimer = null;
    if (full) {
      _tick();
      _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_bind);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _hideTimer?.cancel();
    _tapTimer?.cancel();
    _streakTimer?.cancel();
    _clockTimer?.cancel();
    _seekTimer?.cancel();
    if (_holding) _session.endBoost();
    if (widget.onFullscreen == null) {
      if (_full == true && desktopPlatform) {
        unawaited(setWindowFullScreen(false));
      }
      unawaited(AppDevice.releaseOrientation());
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        ).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.setForeground(playerVisible(state));

  void _bind() {
    final player = _session.player;
    if (identical(player, _bound)) {
      _refresh();
      return;
    }
    _bound = player;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final stream = player.stream;
    _subscriptions.add(
      stream.position.listen((position) {
        final target = _seekTarget;
        if (target != null && (position.inMilliseconds - target).abs() < 1000) {
          _endSeek();
        }
      }),
    );
    _subscriptions.add(
      stream.playing.listen((playing) {
        if (playing) _scheduleHide();
        _refresh();
      }),
    );
    for (final changes in [stream.duration, stream.buffering]) {
      _subscriptions.add(changes.listen((_) => _refresh()));
    }
    _refresh();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _tick() {
    _now = DateTime.now();
    _refresh();
    unawaited(
      AppDevice.battery().then((battery) {
        if (mounted) setState(() => _battery = battery);
      }),
    );
  }

  void _endSeek() {
    _seekTimer?.cancel();
    _seekTarget = null;
    _seekValue = null;
  }

  bool get _pinned =>
      _session.paused || !_session.ready || _dragging || _panel != null;

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _pinned || !_visible) return;
      setState(() => _visible = false);
    });
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    if (_visible && !_pinned) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _show();
    }
  }

  void _tapUp(TapUpDetails details, double width, bool full) {
    final x = details.localPosition.dx;
    final side =
        !full && widget.onFullscreen == null ||
            !_session.store.playbackPreferences.doubleTapSeek
        ? 0
        : x < width / 4
        ? -1
        : x > width * 3 / 4
        ? 1
        : 0;
    if (_streak != 0) {
      if (side == _streak.sign) return _streakTap(side);
      setState(_commitStreak);
    }
    if (_tapTimer?.isActive ?? false) {
      _tapTimer!.cancel();
      if (side == 0) {
        _session.togglePlayback();
      } else {
        _startStreak(side);
      }
      return;
    }
    _tapTimer = Timer(const Duration(milliseconds: 300), _toggleControls);
  }

  void _startStreak(int side) {
    final duration = _session.player.state.duration;
    if (!_session.ready || duration <= Duration.zero) return;
    _streak = side;
    _streakTaps = 0;
    unawaited(HapticFeedback.selectionClick());
    _armStreak();
  }

  void _streakTap(int side) {
    _streakTaps++;
    if (_streakTaps.isEven) {
      _streak += side;
      unawaited(HapticFeedback.selectionClick());
    }
    _armStreak();
  }

  void _armStreak() {
    _streakTimer?.cancel();
    _streakTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(_commitStreak);
    });
    setState(() {});
  }

  void _commitStreak() {
    _streakTimer?.cancel();
    final steps = _streak;
    _streak = 0;
    final state = _session.player.state;
    if (steps == 0 || !_session.ready || state.duration <= Duration.zero) {
      return;
    }
    final target = (state.position.inMilliseconds + steps * 10000).clamp(
      0,
      state.duration.inMilliseconds,
    );
    unawaited(_session.seekTo(Duration(milliseconds: target)));
  }

  void _pressStart() {
    if (!_session.ready) return;
    _session.holdBoost();
    unawaited(HapticFeedback.selectionClick());
    setState(() => _holding = true);
  }

  void _pressEnd() {
    if (!_holding) return;
    _session.endBoost();
    setState(() => _holding = false);
  }

  void _rotate(bool full) => unawaited(
    desktopPlatform
        ? setWindowFullScreen(!full)
        : AppDevice.setPlayerOrientation(
            full ? PlayerOrientation.portrait : PlayerOrientation.landscape,
          ),
  );

  void _back(bool full) {
    if (_panel != null) {
      setState(() => _panel = null);
      _scheduleHide();
    } else if (full) {
      _rotate(true);
    } else if (_selecting) {
      _select(false);
    }
  }

  void _openPanel(_Panel panel) {
    _hideTimer?.cancel();
    setState(() => _panel = panel);
  }

  void _closePanel() {
    setState(() => _panel = null);
    _scheduleHide();
  }

  void _select(bool selecting) => setState(() {
    _selecting = selecting;
    _selected.clear();
  });

  void _saveFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('播放偏好未能保存，请重试')));
  }

  Future<void> _change(Future<void> Function() change) async {
    try {
      await change();
    } catch (_) {
      _saveFailed();
    }
  }

  Future<void> _openSettings() {
    _hideTimer?.cancel();
    return showPlayerSheet(
      context,
      (_) => PlaybackSettings(session: _session, onFailure: _saveFailed),
      dark: false,
    ).whenComplete(() {
      if (mounted) _scheduleHide();
    });
  }

  bool get _canDownload =>
      AppScope.of(context).repository.supportsDownloads &&
      widget.store.canDownload;

  void _download() {
    final detail = _session.detail;
    final episodes = [
      for (final index in _selected.toList()..sort()) detail.episodes[index],
    ];
    _select(false);
    unawaited(downloadEpisodes(context, widget.store, detail, episodes));
  }

  @override
  Widget build(BuildContext context) {
    final full = MediaQuery.orientationOf(context) == Orientation.landscape;
    final theme = Theme.of(context);
    final dark = playerTheme(context);
    final video = Theme(
      data: dark,
      child: Builder(builder: (context) => _video(context, full)),
    );
    return PopScope(
      canPop: !full && !_selecting && _panel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(full);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: full
            ? AppTheme.systemBars(Brightness.dark)
            : AppTheme.systemBars(theme.brightness).copyWith(
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
        child: full
            ? Scaffold(backgroundColor: Colors.black, body: video)
            : Scaffold(
                backgroundColor: theme.colorScheme.surface,
                body: Column(
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: SizedBox(
                        width: double.infinity,
                        height: MediaQuery.paddingOf(context).top,
                      ),
                    ),
                    AspectRatio(aspectRatio: 16 / 9, child: video),
                    Expanded(child: _details(context)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _video(BuildContext context, bool full) {
    final session = _session;
    final visible = _visible || _pinned;
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          key: ValueKey(session.player),
          controller: widget.handle.video(session.player),
          controls: NoVideoControls,
          fill: Colors.black,
          pauseUponEnteringBackgroundMode: false,
        ),
        DanmakuOverlay(
          controller: session.danmaku,
          aspectRatio: session.aspectRatio,
        ),
        SwipeControls(
          session: session,
          enabled: full,
          levels: session.store.playbackPreferences.swipeLevels,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _tapUp(details, constraints.maxWidth, full),
              onLongPressStart: (_) => _pressStart(),
              onLongPressEnd: (_) => _pressEnd(),
              onLongPressCancel: _pressEnd,
            ),
          ),
        ),
        if (session.ready && session.stalled)
          const IgnorePointer(
            child: Center(child: CircularProgressIndicator()),
          ),
        if (session.loading) PlaybackLoading(session: session),
        if (session.error case final error?)
          PlaybackFailure(session: session, error: error),
        if (_streak != 0) _streakBadge(full),
        IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Listener(
              onPointerDown: (_) => _scheduleHide(),
              child: full ? _fullControls(context) : _miniControls(context),
            ),
          ),
        ),
        if (full && !visible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: IgnorePointer(child: _thinProgress(context)),
          ),
        if (session.boosting)
          Positioned(
            left: 0,
            right: 0,
            top: full ? 24 : 12,
            child: IgnorePointer(child: Center(child: _boostBadge())),
          ),
        if (session.saveWarning case final warning?)
          Positioned(
            left: 12,
            right: 12,
            bottom: full ? 120 : 64,
            child: _saveWarning(warning),
          ),
        if (_panel case final panel? when full) ...[
          GestureDetector(
            onTap: _closePanel,
            child: ColoredBox(
              color: panel == _Panel.episodes || panel == _Panel.settings
                  ? const Color(0x4D000000)
                  : Colors.transparent,
            ),
          ),
          if (panel == _Panel.episodes || panel == _Panel.settings)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 360,
              child: _panelBody(context, panel),
            )
          else
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _links[panel]!,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topCenter,
                followerAnchor: Alignment.bottomCenter,
                offset: const Offset(0, -6),
                child: _popup(context, panel),
              ),
            ),
        ],
      ],
    );
  }

  Widget _miniControls(BuildContext context) {
    final session = _session;
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: _Shade(height: 64, top: true),
          ),
        ),
        const IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _Shade(height: 96, top: false),
          ),
        ),
        Positioned(
          left: 4,
          right: 4,
          top: 0,
          height: 48,
          child: Row(
            children: [
              _icon(
                Icons.arrow_back_rounded,
                '返回',
                () => unawaited(Navigator.maybePop(context)),
              ),
              const Spacer(),
              if (widget.onMiniWindow case final onMiniWindow?)
                _icon(Icons.picture_in_picture_alt_rounded, '小窗', onMiniWindow),
              _icon(Icons.settings_rounded, '播放设置', _openSettings),
            ],
          ),
        ),
        Positioned(
          left: 4,
          right: 4,
          bottom: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: const Offset(0, 7),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    height: 20,
                    child: _progress(context, thumb: 6),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    _playButton(size: 40, iconSize: 26),
                    const SizedBox(width: 4),
                    _clock(13),
                    const Spacer(),
                    if (session.danmakuSupported) _danmakuButton(context),
                    _icon(
                      Icons.fullscreen_rounded,
                      '全屏',
                      widget.onFullscreen ?? () => _rotate(false),
                      size: 40,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fullControls(BuildContext context) {
    final session = _session;
    final padding = MediaQuery.viewPaddingOf(context);
    final left = math.max(padding.left, 20.0);
    final right = math.max(padding.right, 20.0);
    const shadow = [Shadow(color: Color(0x66000000), blurRadius: 2)];
    final ready = session.ready;
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: _Shade(height: 110, top: true),
          ),
        ),
        const IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _Shade(height: 150, top: false),
          ),
        ),
        Positioned(
          left: left,
          right: right,
          top: 8,
          height: 56,
          child: Row(
            children: [
              _icon(Icons.arrow_back_rounded, '退出全屏', () => _rotate(true)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.detail.drama.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        shadows: shadow,
                      ),
                    ),
                    Text(
                      '第 ${session.episode.number} 集',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 12,
                        shadows: shadow,
                      ),
                    ),
                  ],
                ),
              ),
              FollowIcon(
                store: widget.store,
                drama: session.detail.drama,
                color: Colors.white,
                activeColor: Theme.of(context).colorScheme.primaryFixedDim,
                size: 22,
                extent: 44,
              ),
              const SizedBox(width: 8),
              if (_battery case final battery?) ...[
                _batteryMark(battery),
                const SizedBox(width: 12),
              ],
              Text(
                '${_two(_now.hour)}:${_two(_now.minute)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              if (session.danmakuSupported) _danmakuButton(context),
              if (widget.onMiniWindow case final onMiniWindow?)
                _icon(Icons.picture_in_picture_alt_rounded, '小窗', onMiniWindow),
              _icon(
                Icons.settings_rounded,
                '播放设置',
                () => _openPanel(_Panel.settings),
              ),
            ],
          ),
        ),
        Positioned(
          left: left + 8,
          right: right + 8,
          bottom: 60,
          height: 28,
          child: _progress(context, thumb: 8),
        ),
        Positioned(
          left: left,
          right: right,
          bottom: 8,
          height: 48,
          child: Row(
            children: [
              _playButton(size: 44, iconSize: 30),
              const SizedBox(width: 4),
              _clock(13),
              const SizedBox(width: 8),
              _icon(
                Icons.skip_previous_rounded,
                '上一集',
                session.hasPrevious
                    ? () => unawaited(session.previous())
                    : null,
                iconSize: 28,
              ),
              _icon(
                Icons.skip_next_rounded,
                '下一集',
                session.hasNext ? () => unawaited(session.next()) : null,
                iconSize: 28,
              ),
              const Spacer(),
              _icon(
                Icons.playlist_play_rounded,
                '选集',
                () => _openPanel(_Panel.episodes),
                iconSize: 28,
              ),
              CompositedTransformTarget(
                link: _links[_Panel.quality]!,
                child: _textButton(
                  session.qualityLabel,
                  '清晰度',
                  ready && !session.local
                      ? () => _openPanel(_Panel.quality)
                      : null,
                ),
              ),
              CompositedTransformTarget(
                link: _links[_Panel.speed]!,
                child: _textButton(
                  '${session.speed}x',
                  '倍速',
                  ready ? () => _openPanel(_Panel.speed) : null,
                  bold: true,
                ),
              ),
              _icon(Icons.fullscreen_exit_rounded, '退出全屏', () => _rotate(true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playButton({required double size, required double iconSize}) {
    final playing = !_session.paused;
    return _icon(
      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      playing ? '暂停' : '播放',
      _session.ready ? _session.togglePlayback : null,
      size: size,
      iconSize: iconSize,
    );
  }

  Widget _clock(double fontSize) => PlaybackProgressBuilder(
    player: _session.player,
    builder: (context) {
      final state = _session.player.state;
      final position = _seekValue != null
          ? Duration(milliseconds: _seekValue!.round())
          : state.position;
      return Text(
        '${formatClock(position)} / ${formatClock(state.duration)}',
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.white.withValues(alpha: .86),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    },
  );

  Widget _danmakuButton(BuildContext context) {
    final enabled = _session.danmakuEnabled;
    return _icon(
      enabled ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
      enabled ? '关闭弹幕' : '打开弹幕',
      () => _change(_session.toggleDanmaku),
      color: enabled ? Theme.of(context).colorScheme.primary : null,
      size: 40,
    );
  }

  Widget _icon(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    double size = 44,
    double iconSize = 24,
    Color? color,
  }) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon),
    iconSize: iconSize,
    tooltip: label,
    color: color ?? Colors.white,
    disabledColor: Colors.white.withValues(alpha: .36),
    style: IconButton.styleFrom(
      fixedSize: Size.square(size),
      padding: EdgeInsets.zero,
    ),
  );

  Widget _textButton(
    String text,
    String label,
    VoidCallback? onPressed, {
    bool bold = false,
  }) => Semantics(
    label: label,
    button: true,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        fixedSize: const Size.fromHeight(40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: .6),
        textStyle: TextStyle(
          fontSize: 14,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      child: Text(text),
    ),
  );

  Widget _progress(BuildContext context, {required double thumb}) =>
      PlaybackProgressBuilder(
        player: _session.player,
        builder: (context) => _progressBar(context, thumb: thumb),
      );

  Widget _progressBar(BuildContext context, {required double thumb}) {
    final session = _session;
    final state = session.player.state;
    final duration = state.duration;
    final seekable = session.ready && duration > Duration.zero;
    final max = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final position = (_seekValue ?? state.position.inMilliseconds.toDouble())
        .clamp(0.0, max);
    final colors = Theme.of(context).colorScheme;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        padding: EdgeInsets.zero,
        activeTrackColor: colors.primary,
        thumbColor: colors.primary,
        inactiveTrackColor: Colors.white.withValues(alpha: .25),
        secondaryActiveTrackColor: Colors.white.withValues(alpha: .4),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumb),
        overlayShape: SliderComponentShape.noOverlay,
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: position,
        max: max,
        secondaryTrackValue: state.buffer.inMilliseconds.toDouble().clamp(
          0.0,
          max,
        ),
        semanticFormatterCallback: (value) =>
            formatClock(Duration(milliseconds: value.round())),
        onChangeStart: seekable
            ? (value) {
                _seekTimer?.cancel();
                _seekTarget = null;
                _hideTimer?.cancel();
                setState(() {
                  _dragging = true;
                  _seekValue = value;
                });
              }
            : null,
        onChanged: seekable
            ? (value) => setState(() => _seekValue = value)
            : null,
        onChangeEnd: (value) {
          _dragging = false;
          if (seekable) {
            _seekTarget = value;
            _seekTimer?.cancel();
            _seekTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(_endSeek);
            });
            unawaited(session.seekTo(Duration(milliseconds: value.round())));
            setState(() {});
          } else {
            setState(_endSeek);
          }
          _scheduleHide();
        },
      ),
    );
  }

  Widget _thinProgress(BuildContext context) => PlaybackProgressBuilder(
    player: _session.player,
    builder: (context) {
      final state = _session.player.state;
      final duration = state.duration.inMilliseconds;
      return LinearProgressIndicator(
        value: duration > 0 ? state.position.inMilliseconds / duration : 0,
        minHeight: 2,
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: Colors.white.withValues(alpha: .2),
      );
    },
  );

  Widget _streakBadge(bool full) {
    final forward = _streak > 0;
    return IgnorePointer(
      child: Align(
        alignment: Alignment(forward ? .75 : -.75, 0),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Icon(
                forward
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                size: 20,
                color: Colors.white,
              ),
              Text(
                '${forward ? '快进' : '快退'} ${_streak.abs() * 10} 秒',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boostBadge() => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Icon(Icons.fast_forward_rounded, size: 16, color: Colors.white),
        Text(
          '2 倍速播放中',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _batteryMark(({int level, bool charging}) battery) {
    const levels = [
      Icons.battery_0_bar_rounded,
      Icons.battery_1_bar_rounded,
      Icons.battery_2_bar_rounded,
      Icons.battery_3_bar_rounded,
      Icons.battery_4_bar_rounded,
      Icons.battery_5_bar_rounded,
      Icons.battery_6_bar_rounded,
      Icons.battery_full_rounded,
    ];
    final level = battery.level.clamp(0, 100);
    return Semantics(
      label: '电量 $level%',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Icon(
            battery.charging
                ? Icons.battery_charging_full_rounded
                : levels[(level * 7 / 100).round()],
            size: 18,
            color: Colors.white,
          ),
          Text(
            '$level%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveWarning(String warning) => Material(
    color: const Color(0xE6322424),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              warning,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _session.saveProgress,
            child: const Text('重试保存'),
          ),
        ],
      ),
    ),
  );

  Widget _panelBody(BuildContext context, _Panel panel) {
    final colors = Theme.of(context).colorScheme;
    final right = MediaQuery.viewPaddingOf(context).right;
    final session = _session;
    final episodes = panel == _Panel.episodes;
    return Material(
      color: colors.surfaceContainerLow.withValues(alpha: .94),
      child: Padding(
        padding: EdgeInsets.only(right: right, top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              children: [
                Text(episodes ? '选集' : '播放设置', style: sheetTitle),
                Expanded(
                  child: Text(
                    episodes ? '共 ${session.detail.episodes.length} 集' : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _closePanel,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭',
                ),
              ],
            ),
            Expanded(
              child: episodes
                  ? EpisodeGrid(
                      episodes: session.detail.episodes,
                      current: session.index,
                      selecting: false,
                      selected: const {},
                      touch: true,
                      onSelectionChanged: () {},
                      onPick: (index) {
                        _closePanel();
                        if (index != session.index) {
                          unawaited(session.play(index));
                        }
                      },
                    )
                  : const StatusView(
                      title: '「播放设置」正在重建',
                      icon: Icons.settings_rounded,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _popup(BuildContext context, _Panel panel) {
    final session = _session;
    return Material(
      color: const Color(0xE0141414),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: panel == _Panel.speed
            ? _options<double>(
                values: playbackSpeeds.reversed.toList(),
                selected: session.speed,
                label: (value) => '${value}x',
                onSelected: (value) => _change(() => session.setSpeed(value)),
              )
            : _options<int>(
                values: [...session.qualities, 0],
                selected: session.quality,
                label: (value) => value == 0 ? '自动' : '${value}P',
                onSelected: (value) => _change(() => session.setQuality(value)),
              ),
      ),
    );
  }

  Widget _options<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required void Function(T) onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final value in values)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                _closePanel();
                onSelected(value);
              },
              child: Container(
                height: 36,
                constraints: const BoxConstraints(minWidth: 72),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Text(
                  label(value),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: value == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: value == selected ? colors.primary : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _details(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, label) in const ['简介', '选集'].indexed)
                    Expanded(child: _tabButton(context, index, label)),
                ],
              ),
            ),
          ),
          Expanded(child: _tab == 0 ? _intro(context) : _episodes(context)),
        ],
      ),
    );
  }

  Widget _tabButton(BuildContext context, int index, String label) {
    final colors = Theme.of(context).colorScheme;
    final selected = _tab == index;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: () => setState(() {
          _tab = index;
          _selecting = false;
          _selected.clear();
        }),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
            if (selected)
              Positioned(
                bottom: 0,
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = _session;
    final drama = session.detail.drama;
    final meta = [
      SourceSite.byId(drama.source).name,
      '共 ${session.detail.episodes.length} 集',
      if (drama.releaseLabel != '状态未知') drama.releaseLabel,
      if (drama.category.isNotEmpty) drama.category,
    ];
    final description = drama.description.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  drama.title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(8, 0),
              child: FollowIcon(
                store: widget.store,
                drama: drama,
                color: colors.onSurfaceVariant,
                activeColor: colors.primary,
                extent: 44,
              ),
            ),
          ],
        ),
        Text(
          meta.join(' · '),
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Text(
          description.isEmpty ? '暂无简介' : description,
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: description.isEmpty
                ? colors.onSurfaceVariant
                : colors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _episodes(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = _session;
    final episodes = session.detail.episodes;
    final drama = session.detail.drama;
    final all = _selected.length == episodes.length;
    final status = drama.releaseLabel == '状态未知'
        ? ''
        : '${drama.releaseLabel} · ';
    final header = SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selecting
                    ? '已选 ${_selected.length} 集'
                    : '$status共 ${episodes.length} 集',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ),
            if (_canDownload && !_selecting)
              IconButton(
                onPressed: () => _select(true),
                icon: const Icon(Icons.download_rounded),
                tooltip: '下载选集',
              ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Expanded(
          child: EpisodeGrid(
            header: header,
            episodes: episodes,
            current: session.index,
            selecting: _selecting,
            selected: _selected,
            touch: true,
            onSelectionChanged: () => setState(() {}),
            onPick: (index) {
              if (index != session.index) unawaited(session.play(index));
            },
          ),
        ),
        if (_selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _select(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    all
                        ? _selected.clear()
                        : _selected.addAll(
                            List.generate(episodes.length, (i) => i),
                          );
                  }),
                  child: Text(all ? '取消全选' : '全选'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : _download,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('下载'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

class _Shade extends StatelessWidget {
  const _Shade({required this.height, required this.top});
  final double height;
  final bool top;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const [Color(0x99000000), Color(0x00000000)],
        ),
      ),
    ),
  );
}
