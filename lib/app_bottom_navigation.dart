import 'dart:ui';

import 'package:flutter/material.dart';

/// 底部导航。可选悬浮胶囊 + 毛玻璃/液态玻璃外观；
/// 选中项使用圆形高亮（HyperOS 风格），不再使用顶部横条。
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

  /// 液态玻璃：更强模糊 + 渐变高光边框。
  final bool liquidGlass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final glass = blurred || liquidGlass;
    final radius = floating ? 30.0 : 0.0;

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
                                  ? destination.selectedIcon ??
                                        destination.icon
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
