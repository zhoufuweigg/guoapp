import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 液态玻璃（liquid glass）效果。
///
/// 视觉算法移植自 SukiSU-Ultra（https://github.com/ShirkNeko/SukiSU-Ultra ，
/// GPL-3.0-or-later）的 `ui/component/liquid`（Lens.kt / Vibrancy.kt /
/// InnerShadow.kt）与 `ui/component/FloatingBottomBar.kt`，其上游为
/// Kyant0/AndroidLiquidGlass（https://github.com/Kyant0/AndroidLiquidGlass ，
/// Apache-2.0）。要点：
///
/// - 玻璃面：对背后内容做饱和度提升（vibrancy，1.5 倍）+ 轻度模糊 +
///   沿圆角矩形边缘带的透镜折射（lens，由 [LiquidGlassSurface] 经
///   `BackdropFilter` + `ImageFilter.shader` 完成）；
/// - 容器色：`surfaceContainer` @ 0.4 罩在折射面之上；
/// - 轮廓高光：沿轮廓的方向光描边（BloomStroke 的简化移植，
///   [GlassRimHighlight]）；
/// - 选中项：独立的玻璃 pill，带深度折射、色散与内阴影
///   （[LiquidGlassPill]）。
///
/// 着色器的滤镜输入纹理恒为整屏快照，形状在屏幕中的位置由
/// [LiquidGlassSurface] 布局后经 `localToGlobal` 取得并传入；形状之外的
/// 输出由着色器裁掉（全透明）。
///
/// 运行环境不支持 `ImageFilter.shader`（非 Impeller 后端）或着色器加载
/// 失败时，[LiquidGlassShaders.available] 为 false，调用方应回退到纯
/// Flutter 的毛玻璃外观。

/// 玻璃面的几何与折射参数（单位：逻辑像素）。
class LiquidGlassStyle {
  const LiquidGlassStyle({
    required this.cornerRadius,
    required this.refractionHeight,
    required this.refractionAmount,
    this.depthEffect = false,
    this.chromaticAberration = 0,
    this.vibrancy = true,
    this.blurRadius = 4,
  });

  /// 圆角半径。
  final double cornerRadius;

  /// 折射作用的边缘带宽度。
  final double refractionHeight;

  /// 折射位移量。
  ///
  /// 注意：Kyant0/AndroidLiquidGlass 与 SukiSU-Ultra 均传入**负值**
  /// （`setFloatUniform("refractionAmount", -refractionAmount)`），折射采样
  /// 点相对当前像素向形状内侧偏移；正值方向相反。Dart 层统一传负值。
  final double refractionAmount;

  /// 深度折射：折射方向额外向形状中心牵引。
  final bool depthEffect;

  /// 色散强度，0 为关闭。
  final double chromaticAberration;

  /// 是否将背景饱和度提升至 1.5 倍。
  final bool vibrancy;

  /// 背景模糊半径。
  final double blurRadius;

  LiquidGlassStyle copyWith({
    double? cornerRadius,
    double? refractionHeight,
    double? refractionAmount,
    bool? depthEffect,
    double? chromaticAberration,
    bool? vibrancy,
    double? blurRadius,
  }) => LiquidGlassStyle(
    cornerRadius: cornerRadius ?? this.cornerRadius,
    refractionHeight: refractionHeight ?? this.refractionHeight,
    refractionAmount: refractionAmount ?? this.refractionAmount,
    depthEffect: depthEffect ?? this.depthEffect,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
    vibrancy: vibrancy ?? this.vibrancy,
    blurRadius: blurRadius ?? this.blurRadius,
  );

  /// 底栏玻璃面（SukiSU `FloatingBottomBar` 基础层参数）。
  static const bar = LiquidGlassStyle(
    cornerRadius: 30,
    refractionHeight: 24,
    refractionAmount: 24,
  );

  /// 顶栏玻璃面：通栏直角（贴屏幕顶边），折射参数与底栏一致。
  static const top = LiquidGlassStyle(
    cornerRadius: 0,
    refractionHeight: 24,
    refractionAmount: 24,
  );

  /// 选中项玻璃 pill 的**按压动画**参数（Kyant0 / SukiSU 拖动 pill 参数，
  /// 随按压进度 0→1 线性出现）：lens(10dp·p, 14dp·p) + depthEffect + 色散。
  ///
  /// **药丸仅透镜，无 blur / vibrancy**：Kyant0 `LiquidBottomTabs` 与
  /// SukiSU `FloatingBottomBar` 的选中 pill 均只挂 `lens(...)`——模糊只属于
  /// 底栏玻璃面。若药丸也模糊，透镜采样的是已抹平高频的模糊内容，边缘扭曲
  /// 不可见，且图标会被「底栏 blur + 药丸 blur」二次糊成团，失去通透感。
  /// 色散对齐 Kyant0：作布尔量启用，着色器 uniform 传 1f。
  static LiquidGlassStyle pillAt(double pressProgress) {
    final p = pressProgress.clamp(0.0, 1.0);
    return LiquidGlassStyle(
      cornerRadius: 28,
      refractionHeight: 10 * p,
      refractionAmount: 14 * p,
      depthEffect: true,
      chromaticAberration: 1,
      vibrancy: false,
      blurRadius: 0,
    );
  }
}

/// 透镜着色器的加载与 uniform 管理。
///
/// `ImageFilter.shader()` 在创建时会快照 uniform（引擎侧 `as_image_filter`
/// 显式拷贝），因此 uniform 变化后必须重建 [ui.ImageFilter]；这里按
/// 「样式 + 形状尺寸 + 形状中心（屏幕坐标）+ 像素比」缓存，稳态场景零分配。
class LiquidGlassShaders {
  LiquidGlassShaders._();

  static const _shaderAsset = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;

  /// 着色器就绪通知：加载完成或确认不可用后自增，用于触发界面重建。
  static final ValueNotifier<int> ready = ValueNotifier<int>(0);

  /// 着色器是否可用（已成功加载）。
  static bool get available => _program != null;

  static final Map<String, _CachedFilter> _cache = {};

  /// 取得 [slot]（'bar' / 'pill'）对应的滤镜；不可用时返回 null。
  ///
  /// [shapeCenter] 为形状中心在根视图（屏幕）坐标系中的逻辑像素位置——
  /// BackdropFilter 的滤镜输入纹理恒为整屏快照，着色器据此定位形状。
  static ui.ImageFilter? filterFor(
    String slot,
    LiquidGlassStyle style,
    Size shapeSize,
    Offset shapeCenter,
    double dpr,
  ) {
    final program = _program;
    if (program == null) return null;
    final key =
        '${style.cornerRadius}|${style.refractionHeight}'
        '|${style.refractionAmount}|${style.depthEffect}'
        '|${style.chromaticAberration}|${style.vibrancy}'
        '|${style.blurRadius}'
        '|${shapeSize.width}x${shapeSize.height}'
        '|${shapeCenter.dx}x${shapeCenter.dy}|$dpr';
    final cached = _cache[slot];
    if (cached != null && cached.key == key) return cached.filter;

    final shader = program.fragmentShader();
    try {
      void set(String name, double value) =>
          shader.getUniformFloat(name).set(value);
      void set2(String name, double x, double y) {
        shader.getUniformFloat(name, 0).set(x);
        shader.getUniformFloat(name, 1).set(y);
      }

      set2('u_shape_center', shapeCenter.dx * dpr, shapeCenter.dy * dpr);
      set2('u_shape_size', shapeSize.width * dpr, shapeSize.height * dpr);
      final r = style.cornerRadius * dpr;
      for (var i = 0; i < 4; i++) {
        shader.getUniformFloat('u_corner_radii', i).set(r);
      }
      set('u_refraction_height', style.refractionHeight * dpr);
      // 与 Kyant0 / SukiSU 一致传负值：折射采样点向形状内侧偏移。
      set('u_refraction_amount', -style.refractionAmount * dpr);
      set('u_depth_effect', style.depthEffect ? 1 : 0);
      // Kyant0 lens() 将 chromaticAberration 作布尔量：着色器 uniform 恒传
      // 1f（见 Lens.kt setFloatUniform("chromaticAberration", 1f)）。
      set('u_chromatic_aberration', style.chromaticAberration > 0 ? 1 : 0);
      set('u_vibrancy', style.vibrancy ? 1 : 0);
      final shaderFilter = ui.ImageFilter.shader(shader);
      // 背景模糊：ImageFilter.compose(outer: shader, inner: blur) —— 先真高斯
      // 模糊再透镜折射，与 Kyant0 效果链（vibrancy→blur→lens）一致。sigma 按
      // AOSP Blur::convertRadiusToSigma：0.57735*radius + 0.5（radius 为设备
      // 像素）；Impeller 对 sigma>4 自动降采样，成本可控。
      if (style.blurRadius <= 0) {
        _cache[slot] = _CachedFilter(key, shaderFilter);
        return shaderFilter;
      }
      final sigma = 0.57735 * style.blurRadius * dpr + 0.5;
      ui.ImageFilter filter;
      try {
        filter = ui.ImageFilter.compose(
          outer: shaderFilter,
          inner: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: ui.TileMode.clamp,
          ),
        );
      } catch (_) {
        // 组合不可用（极少数后端）时退回纯着色器：无模糊但透镜/色散仍生效。
        filter = shaderFilter;
      }
      _cache[slot] = _CachedFilter(key, filter);
      return filter;
    } catch (_) {
      // uniform 名称/布局不匹配或着色器不满足 ImageFilter.shader 约束：
      // 放弃着色器路径，回退纯 Flutter 外观。
      return null;
    }
  }

  /// 启动时预加载；重复调用安全。
  static Future<void> ensureLoaded() async {
    if (_program != null) return;
    if (!ui.ImageFilter.isShaderFilterSupported) {
      ready.value++;
      return;
    }
    try {
      _program = await ui.FragmentProgram.fromAsset(_shaderAsset);
    } catch (_) {
      _program = null;
    }
    ready.value++;
  }
}

class _CachedFilter {
  _CachedFilter(this.key, this.filter);

  final String key;
  final ui.ImageFilter filter;
}

/// 一片液态玻璃：对背后内容做折射，形状为以 [shapeSize] 为中心（屏幕坐标）
/// 的圆角矩形。
///
/// 本组件不绘制任何前景，容器色、高光、内容由调用方叠加在其上。
///
/// 实现要点：`BackdropFilter` + `ImageFilter.shader` 的滤镜输入纹理恒为整屏
/// 快照（引擎 `Canvas::SaveLayer` 对 backdrop filter 的 save layer 做
/// flood_input_coverage），着色器的 `FlutterFragCoord()` 即屏幕像素坐标。
/// 因此形状中心必须由本组件在布局完成后经 `localToGlobal` 取得并传入着色器
/// （见 [LiquidGlassShaders.filterFor]）；首帧位置未知时不渲染，避免玻璃
/// 闪现在错误位置。
///
/// 形状位置随动画逐帧变化时（如选中 pill 的滑动），自行测量会有一帧延迟，
/// 玻璃形状将滞后于视觉位置；此类场景应由调用方直接传入 [shapeCenter]
/// （屏幕坐标，逻辑像素），跳过自测量。
class LiquidGlassSurface extends StatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.slot,
    required this.style,
    required this.shapeSize,
    this.shapeCenter,
  });

  final String slot;
  final LiquidGlassStyle style;
  final Size shapeSize;

  /// 形状中心在根视图（屏幕）坐标系中的逻辑像素位置。
  ///
  /// 为 null 时组件自行测量（存在一帧延迟）；非 null 时直接使用。
  final Offset? shapeCenter;

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  /// 形状中心在根视图（屏幕）坐标系中的逻辑像素位置（自测量路径）。
  Offset? _shapeCenter;

  @override
  void initState() {
    super.initState();
    // 首帧布局完成后取位置，并持续监听布局变化（键盘、旋转等）。
    _schedulePositionUpdate();
  }

  void _schedulePositionUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 调用方显式传入中心时（动画场景）无需自测量。
      if (widget.shapeCenter != null) return;
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size != Size.zero) {
        final center = box.localToGlobal(box.size.center(Offset.zero));
        if (_shapeCenter != center) {
          setState(() => _shapeCenter = center);
        }
      }
      // 位置可能随布局变化而改变；每帧复检（仅在变化时 setState）。
      _schedulePositionUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 调用方显式传入中心时（动画场景），不依赖自测量，避免一帧延迟。
    final center = widget.shapeCenter ?? _shapeCenter;
    if (center == null) return const SizedBox.shrink();
    final filter = LiquidGlassShaders.filterFor(
      widget.slot,
      widget.style,
      widget.shapeSize,
      center,
      MediaQuery.devicePixelRatioOf(context),
    );
    if (filter == null) return const SizedBox.shrink();
    return SizedBox(
      width: widget.shapeSize.width,
      height: widget.shapeSize.height,
      child: BackdropFilter(
        filter: filter,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 玻璃容器色（SukiSU 的 `surfaceContainer @ 0.4`），裁剪在形状内。
///
/// [overlay] 为叠加在 [color] 之上的第二层颜色（已含目标 alpha），用于
/// SukiSU pill 的按压双色 surface（黑 3%·按压进度）。
class GlassTint extends StatelessWidget {
  const GlassTint({
    super.key,
    required this.size,
    required this.radius,
    required this.color,
    this.shadowColor,
    this.overlay,
  });

  final Size size;
  final double radius;
  final Color color;
  final Color? shadowColor;
  final Color? overlay;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size.width,
    height: size.height,
    child: overlay == null
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: color,
              boxShadow: shadowColor == null
                  ? null
                  : [BoxShadow(color: shadowColor!, blurRadius: 10)],
            ),
          )
        : Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: color,
                  boxShadow: shadowColor == null
                      ? null
                      : [BoxShadow(color: shadowColor!, blurRadius: 10)],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: overlay,
                ),
              ),
            ],
          ),
  );
}

/// 沿轮廓的方向光高光描边：BloomStroke（主光 + 次光、双峰）的简化移植。
class GlassRimHighlight extends StatelessWidget {
  const GlassRimHighlight({
    super.key,
    required this.size,
    required this.radius,
    required this.lightDirection,
    this.alpha = 0.75,
    this.secondaryAlpha = 0.3,
  });

  final Size size;
  final double radius;

  /// 指向光源的单位向量，如 `Offset(-1, 0)` 表示光在左侧。
  final Offset lightDirection;
  final double alpha;
  final double secondaryAlpha;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size.width,
    height: size.height,
    child: CustomPaint(
      painter: _RimHighlightPainter(
        radius: radius,
        lightDirection: lightDirection,
        alpha: alpha,
        secondaryAlpha: secondaryAlpha,
      ),
    ),
  );
}

class _RimHighlightPainter extends CustomPainter {
  _RimHighlightPainter({
    required this.radius,
    required this.lightDirection,
    required this.alpha,
    required this.secondaryAlpha,
  });

  final double radius;
  final Offset lightDirection;
  final double alpha;
  final double secondaryAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final center = rect.center;
    final half = rect.longestSide;

    // 主光：亮边贴在受光一侧，向对侧衰减。
    final lightSide = center + lightDirection * half;
    final darkSide = center - lightDirection * half;
    final primary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(lightSide, darkSide, [
        Colors.white.withValues(alpha: alpha),
        Colors.white.withValues(alpha: alpha * 0.12),
      ]);
    canvas.drawRRect(rrect, primary);

    // 次光：自底部向上的柔光（SukiSU secondaryLight 位于底部）。
    final bottom = center + const Offset(0, 1) * half;
    final top = center - const Offset(0, 1) * half;
    final secondary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 2)
      ..shader = ui.Gradient.linear(bottom, top, [
        Colors.white.withValues(alpha: secondaryAlpha),
        Colors.white.withValues(alpha: 0),
      ]);
    canvas.drawRRect(rrect, secondary);
  }

  @override
  bool shouldRepaint(_RimHighlightPainter old) =>
      old.radius != radius ||
      old.lightDirection != lightDirection ||
      old.alpha != alpha ||
      old.secondaryAlpha != secondaryAlpha;
}

/// 形状内侧的柔和阴影：SukiSU `InnerShadow`（形状填充 − 偏移形状反相清除 +
/// 高斯模糊 + 图层 alpha）的移植。
///
/// 默认偏移向下一个模糊半径，阴影带出现在形状上侧内缘（光源在上方）。
class GlassInnerShadow extends StatelessWidget {
  const GlassInnerShadow({
    super.key,
    required this.size,
    required this.radius,
    this.blurRadius = 8,
    this.color = const Color(0x26000000),
    this.alpha = 1,
    this.offset,
  });

  final Size size;

  /// 形状圆角半径。
  final double radius;

  /// 高斯模糊半径（SukiSU InnerShadow.radius）。
  final double blurRadius;

  /// 阴影颜色（含基础 alpha）。
  final Color color;

  /// 整体不透明度（SukiSU 的 layer.alpha，pill 按压时随进度淡入）。
  final double alpha;

  /// 形状偏移量；null 时取向下一个模糊半径（阴影带在形状上侧内缘）。
  final Offset? offset;

  @override
  Widget build(BuildContext context) {
    if (alpha <= 0.001 || blurRadius <= 0) return const SizedBox.shrink();
    return SizedBox(
      width: size.width,
      height: size.height,
      child: CustomPaint(
        painter: _InnerShadowPainter(
          radius: radius,
          blurRadius: blurRadius,
          offset: offset ?? Offset(0, blurRadius),
          color: color.withValues(alpha: color.a * alpha.clamp(0.0, 1.0)),
        ),
      ),
    );
  }
}

class _InnerShadowPainter extends CustomPainter {
  _InnerShadowPainter({
    required this.radius,
    required this.blurRadius,
    required this.offset,
    required this.color,
  });

  final double radius;
  final double blurRadius;
  final Offset offset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()..addRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
    );
    // 离屏层：整体高斯模糊（模糊半径即 blurRadius）。
    canvas.saveLayer(
      rect,
      Paint()
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blurRadius),
    );
    canvas.save();
    canvas.clipPath(path);
    // 形状填充，再以 Clear 混合抹除偏移后的形状 → 仅余偏移反侧的边缘带，
    // 模糊后即为柔和内阴影（SukiSU InnerShadowNode 的图层记录逻辑）。
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(path.shift(offset), Paint()..blendMode = ui.BlendMode.clear);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) =>
      old.radius != radius ||
      old.blurRadius != blurRadius ||
      old.offset != offset ||
      old.color != color;
}

/// 选中项的液态玻璃 pill：SukiSU `FloatingBottomBar` 选中 pill 的完整移植。
///
/// 透镜参数、容器色、内阴影、轮廓高光全部随 [pressProgress]（0→1）线性出现：
/// - 透镜：`lens(10dp·p, 14dp·p)` + 深度折射 + 色散 0.5（见
///   [LiquidGlassStyle.pillAt]）；
/// - 容器色：亮色主题黑 10% / 暗色主题白 10%，随 `1-p` 淡出，叠加黑 3%·p；
/// - 内阴影：模糊半径 8·p、不透明度 p；
/// - 轮廓高光：不透明度 p（静止时无高光，按压时淡入）。
class LiquidGlassPill extends StatelessWidget {
  const LiquidGlassPill({
    super.key,
    required this.size,
    required this.pressProgress,
    this.shapeCenter,
  });

  final Size size;

  /// 按压进度 0→1。
  final double pressProgress;

  /// 形状中心在屏幕坐标系中的位置；null 时组件自行测量（有一帧延迟）。
  /// 滑动动画期间应由调用方逐帧传入。
  final Offset? shapeCenter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final p = pressProgress.clamp(0.0, 1.0);
    // pill 为全圆角胶囊（SukiSU CircleShape）：半径取半高。
    final radius = size.height / 2;
    final style = LiquidGlassStyle.pillAt(p).copyWith(cornerRadius: radius);
    // SukiSU onDrawSurface：基础色随 (1-p) 淡出，叠加黑 3%·p。
    final baseColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.10 * (1 - p),
    );
    final overlay = Colors.black.withValues(alpha: 0.03 * p);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          LiquidGlassSurface(
            slot: 'pill',
            style: style,
            shapeSize: size,
            shapeCenter: shapeCenter,
          ),
          GlassTint(
            size: size,
            radius: radius,
            color: baseColor,
            overlay: p > 0.001 ? overlay : null,
          ),
          GlassInnerShadow(
            size: size,
            radius: radius,
            blurRadius: 8 * p,
            color: Colors.black.withValues(alpha: 0.15),
            alpha: p,
          ),
          if (p > 0.001)
            GlassRimHighlight(
              size: size,
              radius: radius,
              // SukiSU 的 pill 高光光源位于右侧。
              lightDirection: const Offset(1, 0),
              alpha: 0.5 * p,
            ),
        ],
      ),
    );
  }
}

/// 交互辉光：SukiSU `InteractiveHighlight` 的移植。
///
/// 按压期间在 [position]（形状局部坐标）处叠加 additive 白光：满铺
/// 白 6%·[progress] + 径向光斑白 12%·[progress]（半径 = 短边·1.2，
/// smoothstep 衰减近似为 0→50% 实、50%→100% 线性衰减的渐变）。
class InteractiveGlow extends StatelessWidget {
  const InteractiveGlow({
    super.key,
    required this.size,
    required this.position,
    required this.progress,
  });

  final Size size;

  /// 光斑中心（[size] 包围盒内的局部坐标）。
  final Offset position;

  /// 辉光进度 0→1（SukiSU：spring(0.5, 300)）。
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.001) return const SizedBox.shrink();
    return SizedBox(
      width: size.width,
      height: size.height,
      child: CustomPaint(
        painter: _GlowPainter(
          position: position,
          fillColor: Colors.white.withValues(alpha: 0.06 * p),
          spotColor: Colors.white.withValues(alpha: 0.12 * p),
          radius: (size.shortestSide * 1.2).clamp(1.0, double.infinity),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.position,
    required this.fillColor,
    required this.spotColor,
    required this.radius,
  });

  final Offset position;
  final Color fillColor;
  final Color spotColor;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 满铺微光（BlendMode.plus：加法叠加）。
    canvas.drawRect(
      rect,
      Paint()
        ..color = fillColor
        ..blendMode = ui.BlendMode.plus,
    );
    // 跟随选中 pill 的径向光斑。
    final center = Offset(
      position.dx.clamp(0.0, size.width),
      position.dy.clamp(0.0, size.height),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(center, radius, [
          spotColor,
          spotColor,
          const Color(0x00000000),
        ], const [
          0,
          0.5,
          1,
        ]),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.position != position ||
      old.fillColor != fillColor ||
      old.spotColor != spotColor ||
      old.radius != radius;
}

/// 通栏液态玻璃面板（顶栏等场景）：透镜折射 + 容器色 + 可选底边发丝线。
///
/// 面板尺寸由布局约束决定；形状位置由 [LiquidGlassSurface] 自行定位。
class LiquidGlassPanel extends StatelessWidget {
  const LiquidGlassPanel({
    super.key,
    required this.style,
    required this.tint,
    this.slot = 'panel',
    this.bottomBorderColor,
  });

  final LiquidGlassStyle style;

  /// 容器色（罩在折射面之上）。
  final Color tint;

  /// 着色器缓存槽位标识。
  final String slot;

  /// 底边发丝线颜色（顶栏与内容的分界）。
  final Color? bottomBorderColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isEmpty) return const SizedBox.shrink();
      return Stack(
        children: [
          Positioned.fill(
            child: LiquidGlassSurface(
              slot: slot,
              style: style,
              shapeSize: size,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint,
                border: bottomBorderColor == null
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: bottomBorderColor!,
                          width: 0.5,
                        ),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
