import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../playback_preferences.dart';
import '../../playback_session.dart';
import '../app_scope.dart';
import '../theme/app_theme.dart';
import 'danmaku_overlay.dart';
import 'playback_handle.dart';
import 'player_surface.dart';

enum _Menu { speed, quality }

final _arrows = {
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
};

final _confirms = {
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.gameButtonA,
};

class TelevisionPlayerPage extends StatefulWidget {
  const TelevisionPlayerPage({super.key, required this.handle});
  final PlaybackHandle handle;

  @override
  State<TelevisionPlayerPage> createState() => _TelevisionPlayerPageState();
}

class _TelevisionPlayerPageState extends State<TelevisionPlayerPage>
    with WidgetsBindingObserver {
  final _surface = FocusNode(debugLabel: 'tv-player');
  final _bar = FocusNode(debugLabel: 'tv-player-bar');
  final _previous = FocusNode();
  final _play = FocusNode();
  final _next = FocusNode();
  final _danmaku = FocusNode();
  final _speed = FocusNode();
  final _quality = FocusNode();
  final _retry = FocusNode();
  final _options = <FocusNode>[];
  final _links = {for (final menu in _Menu.values) menu: LayerLink()};
  StreamSubscription<bool>? _playing;
  Player? _bound;
  Timer? _hideTimer;
  Timer? _seekCommit;
  Timer? _seekDisplay;
  bool _visible = true;
  bool _failed = false;
  _Menu? _menu;
  Duration? _seekTarget;
  Duration _seekFrom = Duration.zero;
  int _seekOffset = 0;
  bool _seekShown = false;

  PlaybackSession get _session => widget.handle.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    _changed();
    _scheduleHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    unawaited(_playing?.cancel());
    _hideTimer?.cancel();
    _seekCommit?.cancel();
    _seekDisplay?.cancel();
    for (final node in [
      _surface,
      _bar,
      _previous,
      _play,
      _next,
      _danmaku,
      _speed,
      _quality,
      _retry,
      ..._options,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.setForeground(state == AppLifecycleState.resumed);
  }

  void _changed() {
    final player = _session.player;
    if (!identical(player, _bound)) {
      _bound = player;
      unawaited(_playing?.cancel());
      _playing = player.stream.playing.listen((playing) {
        if (!mounted) return;
        playing ? _scheduleHide() : _reveal();
        setState(() {});
      });
    }
    final failed = _session.error != null;
    if (failed == _failed) return;
    _failed = failed;
    _closeMenu(refocus: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (failed) {
        _retry.requestFocus();
      } else {
        _reveal(force: true);
      }
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted ||
          !_visible ||
          _menu != null ||
          !_session.player.state.playing ||
          _session.error != null) {
        return;
      }
      _hide();
    });
  }

  void _hide() {
    _hideTimer?.cancel();
    _surface.requestFocus();
    setState(() => _visible = false);
  }

  void _reveal({bool force = false}) {
    if (_visible && !force) return _scheduleHide();
    setState(() => _visible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible && _menu == null) _play.requestFocus();
    });
    _scheduleHide();
  }

  void _back() {
    if (_menu != null) {
      _closeMenu();
    } else if (_visible) {
      _hide();
    }
  }

  void _step(int seconds) {
    final state = _session.player.state;
    final duration = state.duration;
    if (!_session.ready || duration <= Duration.zero) return;
    if (!(_seekCommit?.isActive ?? false)) {
      _seekFrom = _seekTarget ?? state.position;
      _seekOffset = 0;
    }
    _seekOffset += seconds;
    final target = _seekFrom.inMilliseconds + _seekOffset * 1000;
    _seekDisplay?.cancel();
    _seekCommit?.cancel();
    _seekCommit = Timer(const Duration(milliseconds: 500), _commitSeek);
    setState(() {
      _seekTarget = Duration(
        milliseconds: target.clamp(0, duration.inMilliseconds),
      );
      _seekShown = true;
    });
    if (_visible) _scheduleHide();
  }

  void _commitSeek() {
    final target = _seekTarget;
    if (target == null) return;
    unawaited(_session.seekTo(target));
    _seekDisplay = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _seekShown = false;
        _seekTarget = null;
      });
    });
  }

  void _episode(int direction) {
    if (direction < 0) {
      unawaited(_session.previous());
    } else {
      unawaited(_session.next());
    }
    _reveal();
  }

  Future<void> _change(Future<void> Function() change) async {
    try {
      await change();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放偏好未能保存，请重试')));
    }
  }

  List<FocusNode> get _row => [
    _previous,
    _play,
    _next,
    if (_session.danmakuSupported) _danmaku,
    _speed,
    _quality,
  ];

  bool _enabled(FocusNode node) =>
      node == _previous && _session.hasPrevious ||
      node == _next && _session.hasNext ||
      node == _speed && _session.ready ||
      node == _quality && _session.ready && !_session.local ||
      node == _play ||
      node == _danmaku;

  void _moveInRow(FocusNode from, int direction) {
    final row = _row;
    for (
      var index = row.indexOf(from) + direction;
      index >= 0 && index < row.length;
      index += direction
    ) {
      if (_enabled(row[index])) return row[index].requestFocus();
    }
  }

  List<Object> _values(_Menu menu) => switch (menu) {
    _Menu.speed => playbackSpeeds.reversed.toList(),
    _Menu.quality => [..._session.qualities, 0],
  };

  Object _selected(_Menu menu) => switch (menu) {
    _Menu.speed => _session.speed,
    _Menu.quality => _session.quality,
  };

  FocusNode _button(_Menu menu) => switch (menu) {
    _Menu.speed => _speed,
    _Menu.quality => _quality,
  };

  void _openMenu(_Menu menu) {
    final values = _values(menu);
    while (_options.length < values.length) {
      _options.add(FocusNode());
    }
    _hideTimer?.cancel();
    setState(() => _menu = menu);
    final index = values.indexOf(_selected(menu));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menu == menu) {
        _options[index < 0 ? 0 : index].requestFocus();
      }
    });
  }

  void _closeMenu({bool refocus = true}) {
    final menu = _menu;
    if (menu == null) return;
    setState(() => _menu = null);
    if (refocus) _button(menu).requestFocus();
    _scheduleHide();
  }

  void _pick(_Menu menu, Object value) {
    _closeMenu();
    unawaited(
      _change(
        () => switch (menu) {
          _Menu.speed => _session.setSpeed(value as double),
          _Menu.quality => _session.setQuality(value as int),
        },
      ),
    );
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || _session.error != null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    switch (key) {
      case LogicalKeyboardKey.mediaPlayPause || LogicalKeyboardKey.space:
        if (down) _session.togglePlayback();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaPlay || LogicalKeyboardKey.mediaPause:
        if (down &&
            _session.player.state.playing !=
                (key == LogicalKeyboardKey.mediaPlay)) {
          _session.togglePlayback();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaTrackNext:
        if (down) _episode(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaTrackPrevious:
        if (down) _episode(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaFastForward:
        _step(10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.mediaRewind:
        _step(-10);
        return KeyEventResult.handled;
    }
    if (_menu case final menu?) return _menuKey(menu, key);
    final horizontal = key == LogicalKeyboardKey.arrowLeft
        ? -1
        : key == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (!_visible) {
      if (horizontal != 0) {
        _step(horizontal * 10);
        return KeyEventResult.handled;
      }
      if (_arrows.contains(key) || _confirms.contains(key)) {
        if (down) _reveal();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    _scheduleHide();
    final node = FocusManager.instance.primaryFocus;
    if (node == _bar) {
      if (horizontal != 0) {
        _step(horizontal * 10);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _play.requestFocus();
      } else if (_confirms.contains(key)) {
        if (down) _session.togglePlayback();
      } else if (key != LogicalKeyboardKey.arrowUp) {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (!_arrows.contains(key)) return KeyEventResult.ignored;
    if (node != null && _row.contains(node)) {
      if (horizontal != 0) {
        _moveInRow(node, horizontal);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        _bar.requestFocus();
      }
    } else {
      _play.requestFocus();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _menuKey(_Menu menu, LogicalKeyboardKey key) {
    if (!_arrows.contains(key)) return KeyEventResult.ignored;
    final count = _values(menu).length;
    final index = _options.indexWhere((node) => node.hasPrimaryFocus);
    final step = key == LogicalKeyboardKey.arrowUp
        ? -1
        : key == LogicalKeyboardKey.arrowDown
        ? 1
        : 0;
    final target = index < 0 ? 0 : (index + step).clamp(0, count - 1);
    _options[target].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark
        ? theme
        : AppTheme.build(
            theme.colorScheme.primary,
            Brightness.dark,
            television: true,
          );
    return Theme(
      data: dark,
      child: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          final failed = _session.error != null;
          return PopScope(
            canPop: failed || !_visible && _menu == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _back();
            },
            child: Focus(
              focusNode: _surface,
              autofocus: true,
              onKeyEvent: _key,
              child: Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(
                      key: ValueKey(_session.player),
                      controller: widget.handle.video(_session.player),
                      controls: NoVideoControls,
                      fill: Colors.black,
                      pauseUponEnteringBackgroundMode: false,
                    ),
                    DanmakuOverlay(
                      controller: _session.danmaku,
                      aspectRatio: _session.aspectRatio,
                    ),
                    if (_session.loading) PlaybackLoading(session: _session),
                    if (_session.ready && _session.stalled)
                      const Center(child: CircularProgressIndicator()),
                    if (!_visible && _seekShown) ...[
                      const _Shade(top: false),
                      _bubble(),
                      _progress(bottom: 27, focusable: false),
                    ],
                    ExcludeFocus(
                      excluding: !_visible || failed,
                      child: Visibility(
                        visible: _visible,
                        maintainState: true,
                        child: _controls(context),
                      ),
                    ),
                    if (_session.saveWarning case final warning?)
                      _saveWarning(warning),
                    if (_session.error case final error?)
                      PlaybackFailure(
                        session: _session,
                        error: error,
                        retryFocus: _retry,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final playing = _session.player.state.playing;
    final menu = _menu;
    return Stack(
      fit: StackFit.expand,
      children: [
        const _Shade(top: true),
        const _Shade(top: false),
        Positioned(
          left: televisionInset,
          right: televisionInset,
          top: 27,
          child: Text(
            '${_session.detail.drama.title} 第 ${_session.episode.number} 集',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.3,
              shadows: [Shadow(color: Color(0x66000000), blurRadius: 3)],
            ),
          ),
        ),
        _progress(bottom: 103, focusable: true),
        Positioned(
          left: televisionInset,
          right: televisionInset,
          bottom: 27,
          height: 60,
          child: Row(
            spacing: 12,
            children: [
              _round(
                _previous,
                Icons.skip_previous_rounded,
                '上一集',
                () => _episode(-1),
              ),
              _round(
                _play,
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                playing ? '暂停' : '播放',
                _session.togglePlayback,
                strong: true,
              ),
              _round(_next, Icons.skip_next_rounded, '下一集', () => _episode(1)),
              const Spacer(),
              if (_session.danmakuSupported)
                _pill(
                  _danmaku,
                  _session.danmakuEnabled ? '弹幕 开' : '弹幕 关',
                  _session.danmakuEnabled ? '关闭弹幕' : '打开弹幕',
                  () => unawaited(_change(_session.toggleDanmaku)),
                  color: _session.danmakuEnabled ? colors.primary : null,
                ),
              CompositedTransformTarget(
                link: _links[_Menu.speed]!,
                child: _pill(
                  _speed,
                  '${_session.speed}x',
                  '倍速',
                  () => _openMenu(_Menu.speed),
                ),
              ),
              CompositedTransformTarget(
                link: _links[_Menu.quality]!,
                child: _pill(
                  _quality,
                  _session.qualityLabel,
                  '清晰度',
                  () => _openMenu(_Menu.quality),
                ),
              ),
            ],
          ),
        ),
        if (menu != null)
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _links[menu]!,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              offset: const Offset(0, -20),
              child: _menuBody(menu),
            ),
          ),
      ],
    );
  }

  Widget _bubble() {
    final forward = _seekOffset >= 0;
    return Align(
      alignment: const Alignment(0, -.07),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(
              forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              size: 24,
              color: Colors.white,
            ),
            Text(
              '${forward ? '快进' : '快退'} ${_seekOffset.abs()} 秒',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progress({required double bottom, required bool focusable}) =>
      Positioned(
        left: televisionInset,
        right: televisionInset,
        bottom: bottom,
        height: 28,
        child: PlaybackProgressBuilder(
          player: _session.player,
          builder: (context) => ListenableBuilder(
            listenable: _bar,
            builder: (context, _) => _progressRow(
              focused: focusable && _bar.hasPrimaryFocus,
              focusable: focusable,
            ),
          ),
        ),
      );

  Widget _progressRow({required bool focused, required bool focusable}) {
    final colors = Theme.of(context).colorScheme;
    final state = _session.player.state;
    final duration = state.duration;
    final total = duration.inMilliseconds;
    final position = _seekTarget ?? state.position;
    double fraction(Duration value) =>
        total > 0 ? (value.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    final played = fraction(position);
    final thickness = focused
        ? 8.0
        : _seekShown
        ? 6.0
        : 4.0;
    final knob = focused
        ? 20.0
        : _seekShown
        ? 14.0
        : 0.0;
    const clock = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final track = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final x = width * played;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: thickness,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(thickness / 2),
              ),
            ),
            Container(
              width: width * fraction(state.buffer),
              height: thickness,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .38),
                borderRadius: BorderRadius.circular(thickness / 2),
              ),
            ),
            Container(
              width: x,
              height: thickness,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(thickness / 2),
              ),
            ),
            if (knob > 0)
              Positioned(
                left: x - knob / 2,
                child: Container(
                  width: knob,
                  height: knob,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: focused
                        ? [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: .45),
                              spreadRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            if (focused)
              Positioned(
                left: x,
                bottom: 24,
                child: FractionalTranslation(
                  translation: const Offset(-.5, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x59000000),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      formatClock(position),
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    return Row(
      spacing: 16,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Text(
            formatClock(position),
            style: clock.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: focusable
              ? Semantics(
                  label: '播放进度',
                  value: formatClock(position),
                  child: Focus(focusNode: _bar, child: track),
                )
              : track,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Text(
            formatClock(duration),
            textAlign: TextAlign.right,
            style: clock.copyWith(color: Colors.white.withValues(alpha: .72)),
          ),
        ),
      ],
    );
  }

  Widget _control(
    FocusNode node,
    String label,
    VoidCallback onPressed, {
    required ShapeBorder shape,
    required Widget Function(bool focused, bool enabled) builder,
  }) {
    final enabled = _enabled(node);
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      child: ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          final focused = enabled && node.hasPrimaryFocus;
          return AnimatedScale(
            scale: focused ? 1.08 : 1,
            duration: const Duration(milliseconds: 120),
            child: InkWell(
              focusNode: node,
              canRequestFocus: enabled,
              onTap: enabled ? onPressed : null,
              customBorder: shape,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: builder(focused, enabled),
            ),
          );
        },
      ),
    );
  }

  Decoration _look(bool focused, bool enabled, ShapeBorder shape, double rest) {
    final colors = Theme.of(context).colorScheme;
    return ShapeDecoration(
      shape: shape,
      color: focused
          ? colors.primary
          : Colors.white.withValues(alpha: enabled ? rest : .06),
      shadows: focused
          ? const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ]
          : null,
    );
  }

  Color _ink(bool focused, bool enabled, [Color? color]) {
    if (focused) return Theme.of(context).colorScheme.onPrimary;
    if (!enabled) return Colors.white.withValues(alpha: .3);
    return color ?? Colors.white;
  }

  Widget _round(
    FocusNode node,
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool strong = false,
  }) {
    const shape = CircleBorder();
    return _control(
      node,
      label,
      onPressed,
      shape: shape,
      builder: (focused, enabled) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 52,
        height: 52,
        decoration: _look(focused, enabled, shape, strong ? .22 : .14),
        child: Icon(
          icon,
          size: strong ? 24 : 22,
          color: _ink(focused, enabled),
        ),
      ),
    );
  }

  Widget _pill(
    FocusNode node,
    String text,
    String label,
    VoidCallback onPressed, {
    Color? color,
  }) {
    const shape = StadiumBorder();
    return _control(
      node,
      label,
      onPressed,
      shape: shape,
      builder: (focused, enabled) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: _look(focused, enabled, shape, .14),
        child: Text(
          text,
          style: TextStyle(
            color: _ink(focused, enabled, color),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _menuBody(_Menu menu) {
    final colors = Theme.of(context).colorScheme;
    final values = _values(menu);
    final selected = _selected(menu);
    String label(Object value) => switch (menu) {
      _Menu.speed => '${value}x',
      _Menu.quality => value == 0 ? '自动' : '${value}P',
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xF018181A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            for (final (index, value) in values.indexed)
              ListenableBuilder(
                listenable: _options[index],
                builder: (context, _) {
                  final focused = _options[index].hasPrimaryFocus;
                  final current = value == selected;
                  final color = focused
                      ? colors.onPrimary
                      : current
                      ? colors.primary
                      : Colors.white.withValues(alpha: .88);
                  return Semantics(
                    label: label(value),
                    selected: current,
                    button: true,
                    excludeSemantics: true,
                    child: InkWell(
                      focusNode: _options[index],
                      onTap: () => _pick(menu, value),
                      borderRadius: BorderRadius.circular(10),
                      focusColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.fromLTRB(12, 0, 18, 0),
                        decoration: BoxDecoration(
                          color: focused ? colors.primary : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          spacing: 8,
                          children: [
                            SizedBox(
                              width: 18,
                              child: current
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: color,
                                    )
                                  : null,
                            ),
                            Text(
                              label(value),
                              style: TextStyle(
                                color: color,
                                fontSize: 17,
                                fontWeight: current || focused
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _saveWarning(String warning) => Positioned(
    top: 27,
    left: televisionInset,
    right: televisionInset,
    child: Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xE6322424),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          warning,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    ),
  );
}

class _Shade extends StatelessWidget {
  const _Shade({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: top ? 130 : 190,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: top
                  ? const [Color(0xA6000000), Color(0x00000000)]
                  : const [Color(0x00000000), Color(0xB3000000)],
            ),
          ),
        ),
      ),
    ),
  );
}
