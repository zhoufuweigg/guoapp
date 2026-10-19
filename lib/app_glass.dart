import 'dart:ui';

import 'package:flutter/material.dart';

class GlassEffectScope extends InheritedWidget {
  const GlassEffectScope({
    super.key,
    required this.enabled,
    required super.child,
  });
  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassEffectScope>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(GlassEffectScope oldWidget) =>
      enabled != oldWidget.enabled;
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!GlassEffectScope.of(context)) {
      return Material(color: theme.scaffoldBackgroundColor, child: child);
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Material(
          color: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
          child: child,
        ),
      ),
    );
  }
}
