import 'dart:math' as math;

/// 外观设置：顶栏/底栏模糊、悬浮底栏、液态玻璃、返回手势与全局缩放。
///
/// 主题明暗仍由 [LocalStore.themeMode] 单独保存（沿用原有设置项），
/// 这里只保存其余外观开关，避免同一状态存两份。
class ThemeAppearance {
  const ThemeAppearance({
    this.blurBars = false,
    this.floatingBar = false,
    this.liquidGlass = false,
    this.predictiveBack = true,
    this.swipeBack = false,
    this.scale = 1,
  });

  final bool blurBars;
  final bool floatingBar;
  final bool liquidGlass;
  final bool predictiveBack;
  final bool swipeBack;
  final double scale;

  static const double minScale = 0.8;
  static const double maxScale = 1.3;
  static const double scaleStep = 0.05;

  bool get scaled => (scale - 1).abs() > 0.001;

  ThemeAppearance copyWith({
    bool? blurBars,
    bool? floatingBar,
    bool? liquidGlass,
    bool? predictiveBack,
    bool? swipeBack,
    double? scale,
  }) =>
      ThemeAppearance(
        blurBars: blurBars ?? this.blurBars,
        floatingBar: floatingBar ?? this.floatingBar,
        liquidGlass: liquidGlass ?? this.liquidGlass,
        predictiveBack: predictiveBack ?? this.predictiveBack,
        swipeBack: swipeBack ?? this.swipeBack,
        scale: scale ?? this.scale,
      );

  Map<String, dynamic> toJson() => {
        'blurBars': blurBars,
        'floatingBar': floatingBar,
        'liquidGlass': liquidGlass,
        'predictiveBack': predictiveBack,
        'swipeBack': swipeBack,
        'scale': scale,
      };

  factory ThemeAppearance.fromJson(Map<String, dynamic> value) {
    final rawScale = (value['scale'] as num? ?? 1).toDouble();
    final scale =
        rawScale.isFinite ? rawScale.clamp(minScale, maxScale).toDouble() : 1.0;
    final floating = value['floatingBar'] as bool? ?? false;
    return ThemeAppearance(
      blurBars: value['blurBars'] as bool? ?? false,
      floatingBar: floating,
      // 不变量：液态玻璃只在悬浮底栏上生效，反序列化时归一化，
      // 避免外部数据（快照恢复/手改配置）造成非法组合。
      liquidGlass: (value['liquidGlass'] as bool? ?? false) && floating,
      predictiveBack: value['predictiveBack'] as bool? ?? true,
      swipeBack: value['swipeBack'] as bool? ?? false,
      scale:
          (math.max(minScale, math.min(maxScale, scale)) * 100).round() / 100,
    );
  }
}
