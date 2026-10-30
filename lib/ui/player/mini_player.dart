import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../picture_in_picture.dart';
import '../../playback_session.dart';
import '../app_scope.dart';
import '../widgets/focus_ring.dart';
import 'playback_handle.dart';
import 'player_surface.dart';

bool playerVisible(AppLifecycleState? state) =>
    state == AppLifecycleState.resumed ||
    desktopPlatform && state == AppLifecycleState.inactive ||
    PictureInPicture.instance.keepsPlaying(state);

Widget _video(PlaybackHandle handle) => Video(
  key: ValueKey(handle.session.player),
  controller: handle.video(handle.session.player),
  controls: NoVideoControls,
  fill: Colors.black,
  pauseUponEnteringBackgroundMode: false,
);

const _spinner = IgnorePointer(
  child: Center(
    child: SizedBox.square(
      dimension: 28,
      child: CircularProgressIndicator(strokeWidth: 3),
    ),
  ),
);

class PictureInPictureView extends StatelessWidget {
  const PictureInPictureView({super.key, required this.handle});
  final PlaybackHandle handle;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: handle.session,
    builder: (context, _) {
      final session = handle.session;
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _video(handle),
            if (session.loading || session.ready && session.stalled) _spinner,
          ],
        ),
      );
    },
  );
}

class MiniWindowView extends StatefulWidget {
  const MiniWindowView({
    super.key,
    required this.handle,
    required this.onRestore,
    required this.onClose,
  });
  final PlaybackHandle handle;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  @override
  State<MiniWindowView> createState() => _MiniWindowViewState();
}

class _MiniWindowViewState extends State<MiniWindowView> {
  final _focus = FocusNode(debugLabel: 'miniWindow');
  bool _hover = false;
  double? _seekValue;

  PlaybackSession get _session => widget.handle.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space || LogicalKeyboardKey.mediaPlayPause:
        _session.togglePlayback();
      case LogicalKeyboardKey.escape:
        widget.onRestore();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => KeyboardControls(
    child: Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, _) => StreamBuilder<bool>(
            stream: _session.player.stream.playing,
            initialData: _session.player.state.playing,
            builder: (context, snapshot) =>
                _body(context, playing: snapshot.data ?? false),
          ),
        ),
      ),
    ),
  );

  Widget _body(BuildContext context, {required bool playing}) {
    final session = _session;
    final visible = _hover || !playing || _seekValue != null;
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _video(widget.handle),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => unawaited(windowManager.startDragging()),
            onDoubleTap: widget.onRestore,
          ),
          if (session.loading || session.ready && session.stalled) _spinner,
          if (session.error != null)
            const IgnorePointer(
              child: Center(
                child: Text(
                  '暂时无法播放',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: _controls(context, playing: playing),
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.windows) ..._edges(),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, {required bool playing}) {
    final session = _session;
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: ColoredBox(color: Color(0x59000000))),
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            children: [
              _icon(Icons.open_in_full_rounded, '还原', widget.onRestore),
              _icon(Icons.close_rounded, '关闭', widget.onClose),
            ],
          ),
        ),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(
                Icons.skip_previous_rounded,
                '上一集',
                session.hasPrevious
                    ? () => unawaited(session.previous())
                    : null,
              ),
              _icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                playing ? '暂停' : '播放',
                session.ready ? session.togglePlayback : null,
                size: 48,
                iconSize: 32,
              ),
              _icon(
                Icons.skip_next_rounded,
                '下一集',
                session.hasNext ? () => unawaited(session.next()) : null,
              ),
            ],
          ),
        ),
        Positioned(
          left: 4,
          right: 4,
          bottom: 2,
          height: 20,
          child: PlaybackProgressBuilder(
            player: session.player,
            builder: (context) => _progress(context),
          ),
        ),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final session = _session;
    final state = session.player.state;
    final duration = state.duration.inMilliseconds;
    final max = duration > 0 ? duration.toDouble() : 1.0;
    final enabled = session.ready && duration > 0;
    final colors = Theme.of(context).colorScheme;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: colors.primary,
        thumbColor: colors.primary,
        inactiveTrackColor: Colors.white.withValues(alpha: .25),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: Slider(
        value: (_seekValue ?? state.position.inMilliseconds.toDouble()).clamp(
          0.0,
          max,
        ),
        max: max,
        semanticFormatterCallback: (value) =>
            formatClock(Duration(milliseconds: value.round())),
        onChanged: enabled
            ? (value) => setState(() => _seekValue = value)
            : null,
        onChangeEnd: (value) {
          setState(() => _seekValue = null);
          if (enabled) {
            unawaited(session.seekTo(Duration(milliseconds: value.round())));
          }
        },
      ),
    );
  }

  Widget _icon(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    double size = 36,
    double iconSize = 22,
  }) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon),
    iconSize: iconSize,
    tooltip: label,
    color: Colors.white,
    disabledColor: Colors.white.withValues(alpha: .36),
    style: IconButton.styleFrom(
      fixedSize: Size.square(size),
      padding: EdgeInsets.zero,
    ),
  );

  List<Widget> _edges() {
    const thickness = 6.0;
    const corner = 12.0;
    Widget edge(
      ResizeEdge edge,
      MouseCursor cursor, {
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) => Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => unawaited(windowManager.startResizing(edge)),
        ),
      ),
    );
    return [
      edge(
        ResizeEdge.top,
        SystemMouseCursors.resizeUpDown,
        left: corner,
        right: corner,
        top: 0,
        height: thickness,
      ),
      edge(
        ResizeEdge.bottom,
        SystemMouseCursors.resizeUpDown,
        left: corner,
        right: corner,
        bottom: 0,
        height: thickness,
      ),
      edge(
        ResizeEdge.left,
        SystemMouseCursors.resizeLeftRight,
        left: 0,
        top: corner,
        bottom: corner,
        width: thickness,
      ),
      edge(
        ResizeEdge.right,
        SystemMouseCursors.resizeLeftRight,
        right: 0,
        top: corner,
        bottom: corner,
        width: thickness,
      ),
      edge(
        ResizeEdge.topLeft,
        SystemMouseCursors.resizeUpLeftDownRight,
        left: 0,
        top: 0,
        width: corner,
        height: corner,
      ),
      edge(
        ResizeEdge.bottomRight,
        SystemMouseCursors.resizeUpLeftDownRight,
        right: 0,
        bottom: 0,
        width: corner,
        height: corner,
      ),
      edge(
        ResizeEdge.topRight,
        SystemMouseCursors.resizeUpRightDownLeft,
        right: 0,
        top: 0,
        width: corner,
        height: corner,
      ),
      edge(
        ResizeEdge.bottomLeft,
        SystemMouseCursors.resizeUpRightDownLeft,
        left: 0,
        bottom: 0,
        width: corner,
        height: corner,
      ),
    ];
  }
}
