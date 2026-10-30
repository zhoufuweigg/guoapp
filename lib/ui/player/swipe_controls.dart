import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_device.dart';
import '../../playback_session.dart';
import 'player_surface.dart';

const _seekSpan = 120000;

enum _Level { brightness, volume }

class SwipeControls extends StatefulWidget {
  const SwipeControls({
    super.key,
    required this.session,
    this.enabled = true,
    this.levels = false,
    required this.child,
  });
  final PlaybackSession session;
  final bool enabled;
  final bool levels;
  final Widget child;

  @override
  State<SwipeControls> createState() => _SwipeControlsState();
}

class _SwipeControlsState extends State<SwipeControls> {
  int? _seekFrom;
  double _seekOffset = 0;
  _Level? _level;
  double? _value;
  double _pending = 0;

  PlaybackSession get _session => widget.session;

  int get _duration => _session.player.state.duration.inMilliseconds;

  int get _seekTarget => (_seekFrom! + _seekOffset).round().clamp(0, _duration);

  void _seekStart(DragStartDetails _) {
    if (!_session.ready || _duration <= 0) return;
    setState(() {
      _seekFrom = _session.player.state.position.inMilliseconds;
      _seekOffset = 0;
    });
  }

  void _seekUpdate(DragUpdateDetails details) {
    final from = _seekFrom;
    if (from == null) return;
    final span = math.min(_duration, _seekSpan);
    final offset = _seekOffset + details.delta.dx / context.size!.width * span;
    setState(
      () => _seekOffset = offset.clamp(-from, _duration - from).toDouble(),
    );
  }

  void _seekEnd(DragEndDetails _) {
    if (_seekFrom == null) return;
    final target = _seekTarget;
    setState(() => _seekFrom = null);
    unawaited(_session.seekTo(Duration(milliseconds: target)));
  }

  void _seekCancel() {
    if (_seekFrom != null) setState(() => _seekFrom = null);
  }

  Future<void> _levelStart(DragStartDetails details) async {
    final level = details.localPosition.dx < context.size!.width / 2
        ? _Level.brightness
        : _Level.volume;
    setState(() {
      _level = level;
      _value = null;
      _pending = 0;
    });
    final value = await (level == _Level.brightness
        ? AppDevice.brightness()
        : AppDevice.volume());
    if (!mounted || _level != level || _value != null) return;
    if (value == null) return setState(() => _level = null);
    _apply(value + _pending);
  }

  void _levelUpdate(DragUpdateDetails details) {
    if (_level == null) return;
    final delta = -details.delta.dy / context.size!.height;
    if (_value case final value?) {
      _apply(value + delta);
    } else {
      _pending += delta;
    }
  }

  void _apply(double value) {
    final next = value.clamp(0.0, 1.0);
    setState(() => _value = next);
    unawaited(
      _level == _Level.brightness
          ? AppDevice.setBrightness(next)
          : AppDevice.setVolume(next),
    );
  }

  void _levelEnd() {
    if (_level != null) setState(() => _level = null);
  }

  @override
  Widget build(BuildContext context) {
    final seek =
        widget.enabled &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final levels = seek && widget.levels;
    final level = _level;
    final value = _value;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onHorizontalDragStart: seek ? _seekStart : null,
          onHorizontalDragUpdate: seek ? _seekUpdate : null,
          onHorizontalDragEnd: seek ? _seekEnd : null,
          onHorizontalDragCancel: seek ? _seekCancel : null,
          onVerticalDragStart: levels
              ? (details) => unawaited(_levelStart(details))
              : null,
          onVerticalDragUpdate: levels ? _levelUpdate : null,
          onVerticalDragEnd: levels ? (_) => _levelEnd() : null,
          onVerticalDragCancel: levels ? _levelEnd : null,
          child: widget.child,
        ),
        if (_seekFrom != null)
          _badge(_seekLabel())
        else if (level != null && value != null)
          _badge(_levelBar(level, value)),
      ],
    );
  }

  Widget _badge(Widget child) => IgnorePointer(
    child: Align(
      alignment: const Alignment(0, -.4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    ),
  );

  Widget _seekLabel() => Text.rich(
    TextSpan(
      text: formatClock(Duration(milliseconds: _seekTarget)),
      children: [
        TextSpan(
          text: ' / ${formatClock(_session.player.state.duration)}',
          style: TextStyle(color: Colors.white.withValues(alpha: .6)),
        ),
      ],
    ),
    style: const TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  Widget _levelBar(_Level level, double value) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 10,
    children: [
      Icon(
        level == _Level.brightness
            ? Icons.brightness_6_rounded
            : value == 0
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded,
        size: 22,
        color: Colors.white,
      ),
      SizedBox(
        width: 120,
        child: LinearProgressIndicator(
          value: value,
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
          color: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: .25),
        ),
      ),
    ],
  );
}
