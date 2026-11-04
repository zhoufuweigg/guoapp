import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'app_glass.dart';

/// 底部导航。可选悬浮胶囊 + 毛玻璃/液态玻璃外观；
/// 选中项使用液态玻璃 pill（SukiSU-Ultra 风格），不再使用顶部横条。
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.floating = false,
    this.blurred = false,
    this.liquidGlass = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  /// 类 Apple 的悬浮胶囊底栏。
  final bool floating;

  /// 底栏背景模糊（需要 Scaffold 开启 extendBody 才能看到内容）。
  final bool blurred;

  /// 液态玻璃：SukiSU-Ultra 风格的透镜折射玻璃（见 [LiquidGlassStyle]）。
  final bool liquidGlass;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    // 着色器异步就绪后重建，从回退外观切换到液态玻璃。
    valueListenable: LiquidGlassShaders.ready,
    builder: (context, _, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 液态玻璃需要透镜着色器；不可用时回退纯 Flutter 毛玻璃外观。
    final useLiquidGlass =
        liquidGlass && floating && LiquidGlassShaders.available;
    final glass = useLiquidGlass || blurred;
    final radius = floating ? 30.0 : 0.0;

    if (useLiquidGlass) {
      return _LiquidGlassBottomBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      );
    }

    Widget bar = Row(
      children: [
        for (final (index, destination) in destinations.indexed)
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              selected: index == selectedIndex,
              child: Tooltip(
                message: destination.label,
                excludeFromSemantics: true,
                child: InkWell(
                  key: ValueKey('bottom-nav-$index'),
                  borderRadius: BorderRadius.circular(radius > 0 ? 20 : 0),
                  onTap: () => onDestinationSelected(index),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: floating ? 70 : 68,
                      minWidth: 48,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: floating ? 9 : 9,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 选中项：图标外的浅色圆形高亮（HyperOS 风格）。
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: index == selectedIndex
                                  ? colors.primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: IconTheme(
                              data: IconThemeData(
                                size: 22,
                                color: index == selectedIndex
                                    ? colors.primary
                                    : colors.onSurface.withValues(alpha: 0.78),
                              ),
                              child: index == selectedIndex
                                  ? destination.selectedIcon ?? destination.icon
                                  : destination.icon,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            destination.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.15,
                              letterSpacing: 0.2,
                              fontWeight: index == selectedIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: index == selectedIndex
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (glass) {
      bar = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // 性能：单层 blur（compose 的 ColorFilter 会额外强制一层 saveLayer，
        // 且模糊成本近似随 sigma 平方增长；sigma 20 与 32 视觉差异很小）。
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: liquidGlass ? 20 : 12,
            sigmaY: liquidGlass ? 20 : 12,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surface.withValues(alpha: liquidGlass ? 0.30 : 0.72),
                  colors.surface.withValues(alpha: liquidGlass ? 0.14 : 0.60),
                ],
              ),
            ),
            child: RepaintBoundary(child: bar),
          ),
        ),
      );
    }

    if (floating) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
          ),
          foregroundDecoration: liquidGlass
              ? BoxDecoration(
                  // 液态玻璃高光：顶部亮、中部透明、底部微亮的渐变 + 亮边。
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.38),
                      Colors.white.withValues(alpha: 0.02),
                      Colors.white.withValues(alpha: 0.14),
                    ],
                    stops: const [0, 0.42, 1],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                )
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: liquidGlass
                    ? Colors.white.withValues(alpha: 0.0)
                    : colors.outlineVariant.withValues(alpha: 0.6),
                width: liquidGlass ? 0 : .5,
              ),
              color: glass ? Colors.transparent : colors.surface,
            ),
            child: bar,
          ),
        ),
      );
    }

    return Material(
      color: glass ? Colors.transparent : theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: glass
                    ? colors.outlineVariant.withValues(alpha: 0.4)
                    : colors.outlineVariant,
                width: .5,
              ),
            ),
          ),
          child: bar,
        ),
      ),
    );
  }
}

/// 单维弹簧动画值。
///
/// 目标变化时以当前值/速度为初速度重启 [SpringSimulation]（等价于 Compose
/// `Animatable.animateTo` 的初速度连续性），时间基准为 ticker 的累计耗时
/// （秒）。供 `_LiquidGlassBottomBar` 的动效系统复用。
class _SpringValue {
  _SpringValue(this.value);

  double value;
  double velocity = 0;
  double target = 0;
  SpringSimulation? _sim;
  double _t0 = 0;

  bool get isActive => _sim != null;

  void animateTo(
    double t,
    SpringDescription spec,
    double now, {
    Tolerance tolerance = const Tolerance(distance: 0.001, velocity: 0.001),
  }) {
    if (t == target && (isActive || value == t)) return;
    target = t;
    _sim = SpringSimulation(
      spec,
      value,
      t,
      velocity,
      snapToEnd: true,
      tolerance: tolerance,
    );
    _t0 = now;
  }

  /// 立即跳到 [v]（拖拽跟随、橡皮筋等无需弹簧的场景）。
  void jump(double v) {
    _sim = null;
    value = v;
    velocity = 0;
    target = v;
  }

  void step(double now) {
    final sim = _sim;
    if (sim == null) return;
    final t = now - _t0;
    if (t <= 0) return;
    value = sim.x(t);
    velocity = sim.dx(t);
    if (sim.isDone(t)) {
      _sim = null;
      velocity = 0;
      value = target;
    }
  }
}

/// 液态玻璃底栏：SukiSU-Ultra `FloatingBottomBar` 的完整 Flutter 移植。
///
/// 动效系统（Compose `DampedDragAnimation` 的等价实现）：
/// - 按压：pressProgress 0→1（spring 1/1000），选中 pill 的透镜、轮廓
///   高光、内阴影、双色容器色随之线性出现；全部 tab 图标放大至 1.2 倍、
///   底栏整体外扩 16dp；
/// - pill 位移：spring(1, 1000)，松手后滑到最近 tab 才释放按压；
/// - 速度挤压拉伸：pill 的 scaleX/scaleY 除以/乘以 1∓clamp(速度·k)；
/// - 拖拽：手指横向拖动 pill 目标（面板橡皮筋偏移 4dp），松手吸附到最近
///   tab 并触发选中回调；
/// - 交互辉光：跟随 pill 的 additive 白光（spring 0.5/300）。
class _LiquidGlassBottomBar extends StatefulWidget {
  const _LiquidGlassBottomBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  State<_LiquidGlassBottomBar> createState() => _LiquidGlassBottomBarState();
}

class _LiquidGlassBottomBarState extends State<_LiquidGlassBottomBar>
    with SingleTickerProviderStateMixin {
  // —— SukiSU FloatingBottomBar 几何（逻辑像素）——
  static const _barHeight = 64.0; // SukiSU：Row.height(64.dp)
  static const _pillHeight = 56.0; // SukiSU：pill 高 56.dp
  static const _barPadding = 4.0; // SukiSU：Row.padding(4.dp)
  static const _barRadius = 30.0; // 玻璃面圆角
  static const _barStyle = LiquidGlassStyle.bar;

  // —— DampedDragAnimation 弹簧参数（Compose spring(dampingRatio, stiffness)）——
  static final _pressSpec = _spring(1.0, 1000); // pressProgress
  static final _scaleXSpec = _spring(0.6, 250);
  static final _scaleYSpec = _spring(0.7, 250);
  static final _valueSpec = _spring(1.0, 1000); // pill 位置
  static final _glowSpec = _spring(0.5, 300); // 交互辉光
  static final _panelSpec = _spring(1.0, 300); // 面板回弹

  static const _pressedScale = 78 / 56; // SukiSU：78dp / 56dp
  static const _tabScaleOnPress = 1.2; // 按压期间 tab 图标放大
  static const _barGrowOnPress = 16.0; // 按压期间底栏外扩（dp）
  static const _pillStretchX = 0.75; // 速度挤压：横向系数
  static const _pillStretchY = 0.25; // 速度挤压：纵向系数
  static const _stretchLimit = 0.2; // 挤压幅度上限
  static const _velocityScale = 10.0; // 速度归一化除数
  static const _rubberBandPx = 4.0; // 面板橡皮筋幅度（dp）

  static SpringDescription _spring(double dampingRatio, double stiffness) =>
      SpringDescription(
        mass: 1,
        stiffness: stiffness,
        damping: dampingRatio * 2 * math.sqrt(stiffness),
      );

  late final Ticker _ticker;
  Duration? _lastTick;

  int _selectedIndex = 0;
  bool _releasePending = false;

  // 动效状态（目标只由指针/外部选中改变，弹簧由 ticker 统一推进）。
  final _pressAnim = _SpringValue(0);
  final _scaleX = _SpringValue(1);
  final _scaleY = _SpringValue(1);
  final _pill = _SpringValue(0);
  final _glow = _SpringValue(0);
  final _panel = _SpringValue(0);
  double _pressTarget = 0;
  double _scaleTarget = 1;
  double _pillTarget = 0;
  double _glowTarget = 0;
  double _panelTarget = 0;

  int? _pointerId;
  double _lastX = 0;
  double _panelRaw = 0;

  double _barWidth = 0;
  double _tabWidth = 0;
  Offset _barOrigin = Offset.zero;
  bool _originReady = false;
  final _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _selectedIndex = widget.selectedIndex;
    _pill.jump(_selectedIndex.toDouble());
    _pillTarget = _selectedIndex.toDouble();
    _scheduleOriginUpdate();
  }

  @override
  void didUpdateWidget(_LiquidGlassBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _selectedIndex) {
      // 外部选中变化（侧栏 / Rail 等）：按压 + 滑动 + 到位释放。
      _selectedIndex = widget.selectedIndex;
      _pillTarget = _selectedIndex.toDouble();
      _press();
      _release();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // —— 指针交互（对应 SukiSU 的 inspectDragGestures + gestureModifier）——

  int _indexAt(double x) {
    if (_tabWidth <= 0) return _selectedIndex;
    return ((x - _barPadding) / _tabWidth)
        .floor()
        .clamp(0, widget.destinations.length - 1);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointerId != null) return;
    _pointerId = event.pointer;
    _lastX = event.localPosition.dx;
    // SukiSU onDragStarted：pill 立即滑向按下的 tab，同时进入按压态。
    _pillTarget = _indexAt(_lastX).toDouble();
    _press();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointerId) return;
    final dx = event.localPosition.dx - _lastX;
    _lastX = event.localPosition.dx;
    if (_tabWidth <= 0) return;
    // SukiSU onDrag：pill 目标跟随手指（弹簧滞后追踪）。
    _pillTarget = (_pillTarget + dx / _tabWidth).clamp(
      0,
      widget.destinations.length - 1,
    );
    // 面板橡皮筋：4dp·sign·EaseOut(|累积位移 / 总宽|)。
    _panelRaw += dx;
    final fraction = (_panelRaw / _barWidth).clamp(-1.0, 1.0);
    final band = _rubberBandPx * fraction.sign * _easeOut(fraction.abs());
    _panel.jump(band);
    _panelTarget = band;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointerId) return;
    _pointerId = null;
    // SukiSU onDragStopped：吸附到最近 tab，变化时才回调。
    final target = _pillTarget.round().clamp(
      0,
      widget.destinations.length - 1,
    );
    _pillTarget = target.toDouble();
    if (target != _selectedIndex) {
      _selectedIndex = target;
      widget.onDestinationSelected(target);
    }
    _panelRaw = 0;
    _panelTarget = 0;
    _release();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointerId) return;
    _pointerId = null;
    _pillTarget = _selectedIndex.toDouble();
    _panelRaw = 0;
    _panelTarget = 0;
    _release();
  }

  // —— 按压 / 释放编排（对应 SukiSU DampedDragAnimation.press/release）——

  void _press() {
    _pressTarget = 1;
    _scaleTarget = _pressedScale;
    _glowTarget = 1;
    _ensureTicking();
  }

  void _release() {
    _glowTarget = 0;
    _releasePending = true;
    _maybeRelease();
    _ensureTicking();
  }

  /// SukiSU release()：等待 pill 滑到目标（阈值 = 行程 2.5%）后才释放按压，
  /// 按压期间图标/底栏/pill 的全部效果随之回退。
  void _maybeRelease() {
    if (!_releasePending) return;
    final span = (widget.destinations.length - 1).toDouble();
    if ((_pill.value - _pillTarget).abs() <= math.max(0.001, span * 0.025)) {
      _releasePending = false;
      _pressTarget = 0;
      _scaleTarget = 1;
    }
  }

  // —— ticker ——

  void _ensureTicking() {
    if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null) return;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final now = elapsed.inMicroseconds / 1e6;

    _pressAnim.step(now);
    _scaleX.step(now);
    _scaleY.step(now);
    _pill.step(now);
    _glow.step(now);
    _panel.step(now);

    _maybeRelease();

    // 目标同步：指针事件只改目标，这里统一以当前时间为基准重启弹簧
    // （ImageFilter.shader 的 uniform 为创建时快照，必须重建滤镜）。
    if (_pressTarget != _pressAnim.target) {
      _pressAnim.animateTo(_pressTarget, _pressSpec, now);
    }
    if (_scaleTarget != _scaleX.target) {
      _scaleX.animateTo(_scaleTarget, _scaleXSpec, now);
    }
    if (_scaleTarget != _scaleY.target) {
      _scaleY.animateTo(_scaleTarget, _scaleYSpec, now);
    }
    if (_pillTarget != _pill.target) {
      _pill.animateTo(_pillTarget, _valueSpec, now);
    }
    if (_glowTarget != _glow.target) {
      _glow.animateTo(_glowTarget, _glowSpec, now);
    }
    if (_panelTarget != _panel.target) {
      _panel.animateTo(
        _panelTarget,
        _panelSpec,
        now,
        tolerance: const Tolerance(distance: 0.5, velocity: 0.5),
      );
    }

    final busy =
        _pressAnim.isActive ||
        _scaleX.isActive ||
        _scaleY.isActive ||
        _pill.isActive ||
        _glow.isActive ||
        _panel.isActive ||
        _releasePending;
    if (!busy) {
      _ticker.stop();
      _lastTick = null;
    }
    setState(() {});
  }

  /// 底栏 Stack 在屏幕中的原点（pill 着色器形状中心的基准）。
  ///
  /// 底栏位置静态，仅在布局变化时更新；每帧复检但仅在变化时 setState。
  void _scheduleOriginUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _stackKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size != Size.zero) {
        final origin = box.localToGlobal(Offset.zero);
        if (_barOrigin != origin || !_originReady) {
          _barOrigin = origin;
          _originReady = true;
          setState(() {});
        }
      }
      _scheduleOriginUpdate();
    });
  }

  /// Compose `EaseOut`（CubicBezierEasing(0, 0, 0.58, 1)）。
  static double _easeOut(double t) =>
      const Cubic(0.0, 0.0, 0.58, 1.0).transform(t.clamp(0.0, 1.0));

  // —— 构建 ——

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tabs = widget.destinations.length;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: SizedBox(
        height: _barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            if (barWidth <= 0 || tabs == 0) return const SizedBox.shrink();
            _barWidth = barWidth;
            _tabWidth = (barWidth - 2 * _barPadding) / tabs;
            return _buildBar(theme, colors, isDark, barWidth, tabs);
          },
        ),
      ),
    );
  }

  Widget _buildBar(
    ThemeData theme,
    ColorScheme colors,
    bool isDark,
    double barWidth,
    int tabs,
  ) {
    final tabWidth = _tabWidth;
    final press = _pressAnim.value.clamp(0.0, 1.0);

    // 底栏整体外扩（SukiSU layerBlock：lerp(1, 1 + 16dp/width, pressProgress)）。
    final barScale = 1 + (_barGrowOnPress / barWidth) * press;
    final barW = barWidth * barScale;
    final barH = _barHeight * barScale;
    final barLeft = (barWidth - barW) / 2;
    final barTop = (_barHeight - barH) / 2;

    // pill 位置与速度挤压拉伸（SukiSU pill layerBlock）。
    final pillCenterX = _barPadding + (_pill.value + 0.5) * tabWidth;
    final velocity = _pill.velocity / math.max(1, tabs - 1) / _velocityScale;
    final stretchX = (velocity * _pillStretchX).clamp(
      -_stretchLimit,
      _stretchLimit,
    );
    final stretchY = (velocity * _pillStretchY).clamp(
      -_stretchLimit,
      _stretchLimit,
    );
    final pillScaleX = _scaleX.value / (1 - stretchX);
    final pillScaleY = _scaleY.value * (1 - stretchY);
    final pillW = tabWidth * pillScaleX;
    final pillH = _pillHeight * pillScaleY;
    final panelOffset = _panel.value;
    // pill 中心（底栏局部坐标）：按压缩放以自身中心为基准，位置不变。
    final pillCenter = Offset(pillCenterX + panelOffset, _barHeight / 2);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        key: _stackKey,
        clipBehavior: Clip.none,
        children: [
          // 玻璃面：vibrancy + 高斯模糊 + 透镜折射。
          Positioned(
            left: barLeft,
            top: barTop,
            width: barW,
            height: barH,
            child: IgnorePointer(
              child: LiquidGlassSurface(
                slot: 'bar',
                style: _barStyle,
                shapeSize: Size(barW, barH),
              ),
            ),
          ),
          // 容器色与投影（SukiSU：surfaceContainer @ 0.4 + dropShadow 10dp）。
          Positioned(
            left: barLeft,
            top: barTop,
            width: barW,
            height: barH,
            child: IgnorePointer(
              child: GlassTint(
                size: Size(barW, barH),
                radius: _barRadius * barScale,
                color: colors.surfaceContainer.withValues(alpha: 0.4),
                shadowColor: Colors.black.withValues(
                  alpha: isDark ? 0.2 : 0.1,
                ),
              ),
            ),
          ),
          // 轮廓高光（SukiSU：BloomStroke @ alpha 0.75，光源位于左上）。
          Positioned(
            left: barLeft,
            top: barTop,
            width: barW,
            height: barH,
            child: IgnorePointer(
              child: GlassRimHighlight(
                size: Size(barW, barH),
                radius: _barRadius * barScale,
                lightDirection: const Offset(-1, 0),
                alpha: 0.75,
              ),
            ),
          ),
          // 交互辉光（SukiSU InteractiveHighlight：跟随 pill 的 additive 白光）。
          Positioned(
            left: panelOffset,
            top: 0,
            width: barWidth,
            height: _barHeight,
            child: IgnorePointer(
              child: InteractiveGlow(
                size: Size(barWidth, _barHeight),
                position: pillCenter,
                progress: _glow.value,
              ),
            ),
          ),
          // 内容行（图标 + 标签），按压期间整体放大。
          Positioned(
            left: panelOffset,
            top: 0,
            width: barWidth,
            height: _barHeight,
            child: Padding(
              padding: const EdgeInsets.all(_barPadding),
              child: Row(
                children: [
                  for (final (index, destination)
                      in widget.destinations.indexed)
                    Expanded(child: _buildTab(colors, index, destination, press)),
                ],
              ),
            ),
          ),
          // 选中 pill：透镜 + 双色容器色 + 内阴影 + 高光，覆盖在内容之上
          // （其折射输入含下方图标，与 SukiSU combinedBackdrop 一致）。
          Positioned(
            left: pillCenterX - pillW / 2 + panelOffset,
            top: (_barHeight - pillH) / 2,
            width: pillW,
            height: pillH,
            child: IgnorePointer(
              child: LiquidGlassPill(
                size: Size(pillW, pillH),
                pressProgress: press,
                shapeCenter: _originReady ? _barOrigin + pillCenter : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(
    ColorScheme colors,
    int index,
    NavigationDestination destination,
    double press,
  ) {
    final selected = index == _selectedIndex;
    return Transform.scale(
      key: ValueKey('bottom-nav-$index'),
      // SukiSU：lerp(1, 1.2, pressProgress)，按压期间全部图标放大。
      scale: lerpDouble(1, _tabScaleOnPress, press),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        child: Tooltip(
          message: destination.label,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 22,
                    color: selected
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: 0.78),
                  ),
                  child: selected
                      ? destination.selectedIcon ?? destination.icon
                      : destination.icon,
                ),
                const SizedBox(height: 5),
                Text(
                  destination.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    letterSpacing: 0.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
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
