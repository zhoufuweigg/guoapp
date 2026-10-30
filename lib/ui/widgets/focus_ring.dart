import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';

bool focusVisible(bool focused) =>
    focused &&
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

EditableTextState? focusedTextField() => FocusManager
    .instance
    .primaryFocus
    ?.context
    ?.findAncestorStateOfType<EditableTextState>();

class KeyboardControls extends InheritedWidget {
  const KeyboardControls({super.key, required super.child});

  @override
  bool updateShouldNotify(KeyboardControls oldWidget) => false;
}

bool keyboardControlsFocused() =>
    FocusManager.instance.primaryFocus?.context
        ?.getInheritedWidgetOfExactType<KeyboardControls>() !=
    null;

bool textFieldKeepsKey(LogicalKeyboardKey key) {
  final value = focusedTextField()?.textEditingValue;
  if (value == null) return false;
  final selection = value.selection;
  return switch (key) {
    LogicalKeyboardKey.arrowLeft =>
      !selection.isCollapsed || selection.extentOffset > 0,
    LogicalKeyboardKey.arrowRight =>
      !selection.isCollapsed || selection.extentOffset < value.text.length,
    _ => false,
  };
}

typedef _Outline = ({
  LayerLink link,
  double radius,
  double spread,
  Color color,
});

typedef _Ring = ({
  Rect rect,
  double radius,
  double stroke,
  Rect clip,
  Color color,
});

_Ring _lerpRing(_Ring a, _Ring b, double t) => (
  rect: Rect.lerp(a.rect, b.rect, t)!,
  radius: lerpDouble(a.radius, b.radius, t)!,
  stroke: lerpDouble(a.stroke, b.stroke, t)!,
  clip: Rect.lerp(a.clip, b.clip, t)!,
  color: Color.lerp(a.color, b.color, t)!,
);

final _outlineLayout = ValueNotifier<Size>(Size.zero);
final _focusedOutline = ValueNotifier<_FocusOutlineState?>(null);
final _outlineMoving = ValueNotifier(false);

void revealFocus(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final box = node.context?.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    box.showOnScreen(rect: (Offset.zero & box.size).inflate(16));
  }
}

class FocusOutlineScrollBehavior extends MaterialScrollBehavior {
  const FocusOutlineScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final indicator = super.buildOverscrollIndicator(context, child, details);
    return axisDirectionToAxis(details.direction) == Axis.vertical
        ? FocusOutlineLayer(child: indicator)
        : indicator;
  }
}

class _OutlineScope extends InheritedWidget {
  const _OutlineScope({
    required this.shown,
    required this.area,
    required super.child,
  });
  final ValueNotifier<_Outline?> shown;
  final BuildContext area;

  @override
  bool updateShouldNotify(_OutlineScope oldWidget) =>
      shown != oldWidget.shown || area != oldWidget.area;
}

class FocusOutlineLayer extends StatefulWidget {
  const FocusOutlineLayer({super.key, required this.child});
  final Widget child;

  @override
  State<FocusOutlineLayer> createState() => _FocusOutlineLayerState();
}

class _FocusOutlineLayerState extends State<FocusOutlineLayer> {
  final _shown = ValueNotifier<_Outline?>(null);

  @override
  Widget build(BuildContext context) => _OutlineScope(
    shown: _shown,
    area: context,
    child: ClipRect(
      child: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [
          widget.child,
          ValueListenableBuilder(
            valueListenable: _shown,
            builder: (context, outline, _) => switch (outline) {
              final outline? => Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(
                  child: CompositedTransformFollower(
                    link: outline.link,
                    showWhenUnlinked: false,
                    child: CustomPaint(painter: _OutlinePainter(outline)),
                  ),
                ),
              ),
              null => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    ),
  );
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.outline)
    : super(repaint: Listenable.merge([_outlineLayout, _outlineMoving]));
  final _Outline outline;

  @override
  void paint(Canvas canvas, Size size) {
    final leader = outline.link.leaderSize;
    if (leader == null || _outlineMoving.value) return;
    final inset = outline.spread - 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & leader).inflate(inset),
        Radius.circular(outline.radius + inset),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = outline.color,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) =>
      oldDelegate.outline != outline;
}

class FocusOutlineMotion extends StatefulWidget {
  const FocusOutlineMotion({super.key, required this.child});
  final Widget child;

  @override
  State<FocusOutlineMotion> createState() => _FocusOutlineMotionState();
}

class _FocusOutlineMotionState extends State<FocusOutlineMotion>
    with SingleTickerProviderStateMixin {
  late final _motion =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 150),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _outlineMoving.value = false;
      });
  _FocusOutlineState? _target;
  _Ring? _from;
  _Ring? _drawn;
  bool _syncing = false;
  bool _sampling = false;
  bool _television = false;

  @override
  void initState() {
    super.initState();
    _focusedOutline.addListener(_scheduleSync);
  }

  @override
  void dispose() {
    _focusedOutline.removeListener(_scheduleSync);
    _motion.dispose();
    if (_outlineMoving.value) _outlineMoving.value = false;
    super.dispose();
  }

  _Ring? _current() {
    final root = context.findRenderObject();
    if (root is! RenderBox) return null;
    final to = _target?._ring(root);
    if (!_motion.isAnimating) return to;
    final from = _from;
    if (to == null || from == null) return null;
    return _lerpRing(from, to, Curves.easeOutCubic.transform(_motion.value));
  }

  void _scheduleSync() {
    if (_syncing) return;
    _syncing = true;
    scheduleMicrotask(_sync);
  }

  void _sync() {
    _syncing = false;
    final next = _focusedOutline.value;
    if (!mounted || next == _target) return;
    final previous = _target;
    final from = _drawn;
    _target = next;
    _drawn = null;
    _track();
    if (next == null ||
        from == null ||
        !_television ||
        previous?._route != next._route) {
      _motion.stop();
      _outlineMoving.value = false;
      return;
    }
    _from = from;
    _outlineMoving.value = true;
    _motion.forward(from: 0);
  }

  void _track() {
    if (_sampling || _target == null) return;
    _sampling = true;
    WidgetsBinding.instance.addPostFrameCallback(_sample);
  }

  void _sample(Duration _) {
    _sampling = false;
    final target = _target;
    if (!mounted || target == null) return;
    if (_motion.isAnimating || target._outline != null) {
      _drawn = _current() ?? _drawn;
    }
    _track();
  }

  @override
  Widget build(BuildContext context) {
    _television = AppScope.of(context).television;
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _MotionPainter(this)),
          ),
        ),
      ],
    );
  }
}

class _MotionPainter extends CustomPainter {
  _MotionPainter(this.motion)
    : super(repaint: Listenable.merge([motion._motion, _outlineMoving]));
  final _FocusOutlineMotionState motion;

  @override
  void paint(Canvas canvas, Size size) {
    if (!motion._motion.isAnimating) return;
    final ring = motion._current();
    if (ring == null) return;
    canvas
      ..save()
      ..clipRect(ring.clip)
      ..drawRRect(
        RRect.fromRectAndRadius(ring.rect, Radius.circular(ring.radius)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.stroke
          ..color = ring.color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_MotionPainter oldDelegate) =>
      oldDelegate.motion != motion;
}

class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLayoutProbe();
}

class _RenderLayoutProbe extends RenderProxyBox {
  @override
  void performLayout() {
    super.performLayout();
    _outlineLayout.value = size;
  }
}

class FocusOutline extends StatefulWidget {
  const FocusOutline({
    super.key,
    required this.visible,
    required this.radius,
    required this.child,
    this.offset = 3,
  });
  final bool visible;
  final double radius;
  final Widget child;
  final double offset;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  final _link = LayerLink();
  final _child = GlobalKey();
  _Outline? _outline;
  ValueNotifier<_Outline?>? _shown;
  BuildContext? _area;
  ModalRoute<Object?>? _route;
  Color _color = Colors.transparent;
  bool _active = true;

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<_OutlineScope>();
    _shown = scope?.shown;
    _area = scope?.area;
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _outline = null;
    _publish();
    super.dispose();
  }

  void _publish() {
    final shown = _shown;
    if (shown == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outline case final outline? when mounted) {
        shown.value = outline;
        _focusedOutline.value = this;
      } else {
        if (shown.value?.link == _link) shown.value = null;
        if (_focusedOutline.value == this) _focusedOutline.value = null;
      }
    });
  }

  _Ring? _ring(RenderBox root) {
    if (!mounted || !_active) return null;
    final box = _child.currentContext?.findRenderObject();
    final area = _area?.findRenderObject();
    if (box is! RenderBox ||
        area is! RenderBox ||
        !box.attached ||
        !area.attached ||
        !box.hasSize ||
        !area.hasSize) {
      return null;
    }
    final inset = widget.offset + 1.5;
    final local = (Offset.zero & box.size).inflate(inset);
    final rect = MatrixUtils.transformRect(box.getTransformTo(root), local);
    final scale = rect.width / local.width;
    return (
      rect: rect,
      radius: math.min((widget.radius + inset) * scale, rect.shortestSide / 2),
      stroke: 3 * scale,
      clip: MatrixUtils.transformRect(
        area.getTransformTo(root),
        Offset.zero & area.size,
      ),
      color: _color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _color = AppScope.of(context).television
        ? colors.onSurface
        : colors.primary;
    final _Outline? outline = widget.visible
        ? (
            link: _link,
            radius: widget.radius,
            spread: widget.offset + 3,
            color: _color,
          )
        : null;
    if (outline != _outline) {
      _outline = outline;
      _publish();
    }
    final child = KeyedSubtree(key: _child, child: widget.child);
    return widget.visible
        ? CompositedTransformTarget(
            link: _link,
            child: _LayoutProbe(child: child),
          )
        : child;
  }
}

class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.radius,
    required this.child,
    this.offset = 3,
    this.scale = 1.06,
  });
  final double radius;
  final Widget child;
  final double offset;
  final double scale;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final visible = focusVisible(_focused);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedScale(
        scale: visible && AppScope.of(context).television ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        child: FocusOutline(
          visible: visible,
          radius: widget.radius,
          offset: widget.offset,
          child: widget.child,
        ),
      ),
    );
  }
}

class FocusPill extends StatelessWidget {
  const FocusPill({
    super.key,
    required this.focusNode,
    required this.selected,
    required this.textStyle,
    required this.child,
  });
  final FocusNode focusNode;
  final bool selected;
  final TextStyle? textStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 120);
    final colors = Theme.of(context).colorScheme;
    final television = AppScope.of(context).television;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final focused =
            television && selected && focusVisible(focusNode.hasPrimaryFocus);
        final style = DefaultTextStyle.of(context).style.merge(textStyle);
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: duration,
          child: AnimatedContainer(
            duration: duration,
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: focused
                  ? colors.primary
                  : colors.secondaryContainer.withValues(
                      alpha: selected ? 1 : 0,
                    ),
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: AnimatedDefaultTextStyle(
                duration: duration,
                style: style.copyWith(
                  color: focused
                      ? colors.onPrimary
                      : selected
                      ? colors.onSecondaryContainer
                      : style.color,
                ),
                child: child!,
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class TileFocus extends StatefulWidget {
  const TileFocus({super.key, required this.builder});
  final Widget Function(FocusNode focusNode) builder;

  @override
  State<TileFocus> createState() => _TileFocusState();
}

class _TileFocusState extends State<TileFocus> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_changed);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final tile = widget.builder(_focusNode);
    if (!AppScope.of(context).television) return tile;
    return Theme(
      data: Theme.of(context).copyWith(focusColor: Colors.transparent),
      child: FocusOutline(
        visible: focusVisible(_focusNode.hasPrimaryFocus),
        radius: 20,
        offset: -3,
        child: tile,
      ),
    );
  }
}
