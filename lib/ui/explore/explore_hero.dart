import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models.dart';
import '../app_scope.dart';
import '../widgets/cover_backdrop.dart';
import '../widgets/cover_image.dart';
import '../widgets/drama_grid.dart';
import '../widgets/focus_ring.dart';

const _shade = Color(0xFF161214);

typedef _HeroMetrics = ({
  double design,
  double height,
  double radius,
  EdgeInsets padding,
  Size cover,
  double coverRadius,
  double gap,
  double? width,
  double title,
  double meta,
  double button,
  bool detail,
});

_HeroMetrics _scale(_HeroMetrics base, double k) => (
  design: base.design,
  height: base.height * k,
  radius: base.radius * k,
  padding: base.padding * k,
  cover: base.cover * k,
  coverRadius: base.coverRadius * k,
  gap: base.gap * k,
  width: switch (base.width) {
    final width? => width * k,
    null => null,
  },
  title: base.title * k,
  meta: base.meta * k,
  button: base.button * k,
  detail: base.detail,
);

class ExploreHero extends StatelessWidget {
  const ExploreHero({
    super.key,
    required this.drama,
    required this.kicker,
    required this.meta,
    required this.action,
    required this.onPlay,
    required this.onDetail,
    this.progress,
  });
  final Drama drama;
  final String kicker;
  final String meta;
  final String action;
  final VoidCallback onPlay;
  final VoidCallback onDetail;
  final double? progress;

  _HeroMetrics _metrics(BuildContext context) =>
      switch (AppScope.formFactorOf(context)) {
        FormFactor.phone => (
          design: 358,
          height: 196,
          radius: 20,
          padding: const EdgeInsets.all(16),
          cover: const Size(109, 164),
          coverRadius: 12,
          gap: 16,
          width: null,
          title: 20,
          meta: 13,
          button: 40,
          detail: false,
        ),
        FormFactor.window => (
          design: 1312,
          height: 232,
          radius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          cover: const Size(128, 192),
          coverRadius: 14,
          gap: 24,
          width: 520,
          title: 28,
          meta: 14,
          button: 40,
          detail: true,
        ),
        FormFactor.pad => (
          design: 914,
          height: 224,
          radius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          cover: const Size(123, 184),
          coverRadius: 14,
          gap: 24,
          width: 440,
          title: 26,
          meta: 14,
          button: 44,
          detail: true,
        ),
        FormFactor.television => (
          design: 844,
          height: 196,
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          cover: const Size(107, 160),
          coverRadius: 12,
          gap: 22,
          width: 420,
          title: 26,
          meta: 14,
          button: 40,
          detail: true,
        ),
      };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final base = _metrics(context);
      final k = math.max(
        1.0,
        dramaTileWidth(context, constraints.maxWidth) /
            dramaTileWidth(context, base.design),
      );
      return _hero(context, _scale(base, k), k);
    },
  );

  Widget _hero(BuildContext context, _HeroMetrics metrics, double k) {
    final colors = Theme.of(context).colorScheme;
    final television = AppScope.of(context).television;
    final muted = Colors.white.withValues(alpha: 0.78);
    final buttonSize = Size(0, metrics.button);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6 * k,
      children: [
        Text(
          kicker,
          style: TextStyle(
            fontSize: metrics.meta - 1,
            fontWeight: FontWeight.w500,
            height: 1.3,
            color: muted,
          ),
        ),
        Text(
          drama.title,
          maxLines: metrics.detail ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: metrics.title,
            fontWeight: FontWeight.w800,
            height: 1.3,
            color: Colors.white,
          ),
        ),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: metrics.meta, height: 1.3, color: muted),
        ),
        if (progress case final progress?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              color: colors.primaryFixedDim,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
              stopIndicatorColor: Colors.transparent,
            ),
          ),
        Expanded(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              spacing: 12 * k,
              children: [
                FocusRing(
                  radius: 999,
                  child: FilledButton.icon(
                    autofocus: television,
                    onPressed: onPlay,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primaryFixedDim,
                      foregroundColor: colors.onPrimaryFixed,
                      minimumSize: buttonSize,
                      padding: EdgeInsets.fromLTRB(14 * k, 0, 20 * k, 0),
                      iconSize: 18 * k,
                      textStyle: TextStyle(
                        fontSize: metrics.meta,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(action),
                  ),
                ),
                if (metrics.detail)
                  FocusRing(
                    radius: 999,
                    child: FilledButton(
                      onPressed: onDetail,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                        minimumSize: buttonSize,
                        padding: EdgeInsets.symmetric(horizontal: 20 * k),
                        textStyle: TextStyle(fontSize: metrics.meta),
                      ),
                      child: const Text('详情'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      label: kicker,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(metrics.radius),
        child: SizedBox(
          height: metrics.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: _shade.withValues(alpha: 0.9)),
              CoverBackdrop(
                drama: drama,
                sigma: 40,
                overlay: LinearGradient(
                  stops: metrics.detail ? const [0, 0.55, 1] : const [0, 1],
                  colors: metrics.detail
                      ? [
                          _shade.withValues(alpha: 0.9),
                          _shade.withValues(alpha: 0.7),
                          _shade.withValues(alpha: 0.2),
                        ]
                      : [
                          _shade.withValues(alpha: 0.88),
                          _shade.withValues(alpha: 0.55),
                        ],
                ),
              ),
              Padding(
                padding: metrics.padding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: metrics.gap,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          metrics.coverRadius,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x59000000),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SizedBox.fromSize(
                        size: metrics.cover,
                        child: DramaCover(
                          drama: drama,
                          radius: metrics.coverRadius,
                          details: false,
                        ),
                      ),
                    ),
                    if (metrics.width case final width?)
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: width),
                          child: info,
                        ),
                      )
                    else
                      Expanded(child: info),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
