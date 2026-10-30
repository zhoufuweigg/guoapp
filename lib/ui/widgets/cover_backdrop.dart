import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models.dart';
import '../app_scope.dart';
import 'cover_image.dart';

class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({
    super.key,
    required this.drama,
    required this.overlay,
    this.sigma = 32,
    this.opacity = 0.85,
  });
  final Drama drama;
  final Gradient overlay;
  final double sigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: Opacity(
            opacity: opacity,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.clamp,
              ),
              child: DramaCover.imagesDisabled || drama.id.isEmpty
                  ? fallback
                  : CoverImage(
                      key: ValueKey('${drama.id}\u0000${drama.cover}'),
                      drama: drama,
                      repository: AppScope.of(context).repository,
                      placeholder: fallback,
                      retryable: false,
                    ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(decoration: BoxDecoration(gradient: overlay)),
        ),
      ],
    );
  }
}
