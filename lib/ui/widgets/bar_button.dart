import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'focus_ring.dart';

class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final television = AppScope.of(context).television;
    return FocusRing(
      radius: 999,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: television ? 20 : 22),
        style: IconButton.styleFrom(
          fixedSize: television ? const Size.square(40) : null,
          minimumSize: television ? const Size.square(40) : null,
          backgroundColor: television ? colors.surfaceContainerHigh : null,
          foregroundColor: television
              ? colors.onSurface
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
