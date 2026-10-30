import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'focus_ring.dart';

class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label);
  final T value;
  final String label;
}

class ChoiceGrid {
  const ChoiceGrid({
    required this.phone,
    required this.wide,
    required this.television,
    required this.wideWidth,
    required this.televisionWidth,
  });
  final int phone;
  final int wide;
  final int television;
  final double wideWidth;
  final double televisionWidth;

  static const sources = ChoiceGrid(
    phone: 3,
    wide: 3,
    television: 2,
    wideWidth: 420,
    televisionWidth: 400,
  );
  static const categories = ChoiceGrid(
    phone: 4,
    wide: 5,
    television: 4,
    wideWidth: 520,
    televisionWidth: 440,
  );
}

typedef ChoiceAction = ({String label, IconData icon, VoidCallback onPressed});

Future<T?> showChoicePanel<T>({
  required BuildContext context,
  required String title,
  required List<ChoiceOption<T>> options,
  required T? selected,
  required ChoiceGrid grid,
  ChoiceAction? action,
}) {
  final form = AppScope.formFactorOf(context);
  Widget panel(BuildContext context) => _ChoicePanel<T>(
    form: form,
    title: title,
    options: options,
    selected: selected,
    columns: switch (form) {
      FormFactor.phone => grid.phone,
      FormFactor.pad || FormFactor.window => grid.wide,
      FormFactor.television => grid.television,
    },
    action: action,
  );
  final navigator = Navigator.of(context);
  switch (form) {
    case FormFactor.phone:
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxHeight: 640),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        builder: panel,
      );
    case FormFactor.pad || FormFactor.window:
      final overlay =
          navigator.overlay!.context.findRenderObject()! as RenderBox;
      final anchor = context.findRenderObject()! as RenderBox;
      final rect =
          anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
      return navigator.push(
        _AnchoredRoute<T>(
          anchor: rect,
          width: grid.wideWidth,
          builder: panel,
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
        ),
      );
    case FormFactor.television:
      return showGeneralDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, _) => Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            elevation: 8,
            child: SizedBox(
              width: grid.televisionWidth,
              height: double.infinity,
              child: panel(context),
            ),
          ),
        ),
        transitionBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
  }
}

class _ChoicePanel<T> extends StatelessWidget {
  const _ChoicePanel({
    required this.form,
    required this.title,
    required this.options,
    required this.selected,
    required this.columns,
    required this.action,
  });
  final FormFactor form;
  final String title;
  final List<ChoiceOption<T>> options;
  final T? selected;
  final int columns;
  final ChoiceAction? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final television = form == FormFactor.television;
    final spacing = television ? 12.0 : 8.0;
    final header = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: (television ? text.headlineSmall : text.titleLarge)
                    ?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: television || form == FormFactor.phone
                          ? null
                          : 17,
                    ),
              ),
              Text(
                '${options.length} 个',
                style: (television ? text.bodyMedium : text.bodySmall)
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (form == FormFactor.phone)
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );
    return Padding(
      padding: switch (form) {
        FormFactor.phone => const EdgeInsets.fromLTRB(16, 0, 4, 20),
        FormFactor.pad ||
        FormFactor.window => const EdgeInsets.fromLTRB(16, 12, 16, 12),
        FormFactor.television => const EdgeInsets.fromLTRB(32, 36, 48, 32),
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          SizedBox(height: television ? 20 : 12),
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                right: form == FormFactor.phone ? 12 : 0,
              ),
              child: GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.all(television ? 12 : 6),
                itemCount: options.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  mainAxisExtent: switch (form) {
                    FormFactor.phone => 44,
                    FormFactor.pad || FormFactor.window => 36,
                    FormFactor.television => 48,
                  },
                ),
                itemBuilder: (context, index) => _ChoiceCell<T>(
                  option: options[index],
                  selected: options[index].value == selected,
                  form: form,
                ),
              ),
            ),
          ),
          if (action case final action?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FocusRing(
                radius: 999,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    action.onPressed();
                  },
                  icon: Icon(action.icon),
                  label: Text(action.label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceCell<T> extends StatelessWidget {
  const _ChoiceCell({
    required this.option,
    required this.selected,
    required this.form,
  });
  final ChoiceOption<T> option;
  final bool selected;
  final FormFactor form;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = switch (form) {
      FormFactor.phone => 12.0,
      FormFactor.pad || FormFactor.window => 10.0,
      FormFactor.television => 14.0,
    };
    return FocusRing(
      radius: radius,
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: selected
              ? BorderSide.none
              : BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: selected,
          focusColor: Colors.transparent,
          onTap: () => Navigator.pop(context, option.value),
          child: Semantics(
            selected: selected,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: form == FormFactor.television ? 15 : 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchoredRoute<T> extends PopupRoute<T> {
  _AnchoredRoute({
    required this.anchor,
    required this.width,
    required this.builder,
    required this.barrierLabel,
  });
  final Rect anchor;
  final double width;
  final WidgetBuilder builder;
  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(BuildContext context, _, _) {
    final colors = Theme.of(context).colorScheme;
    return CustomSingleChildLayout(
      delegate: _AnchoredLayout(anchor, width),
      child: Material(
        color: colors.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: builder(context),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    _,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}

class _AnchoredLayout extends SingleChildLayoutDelegate {
  const _AnchoredLayout(this.anchor, this.width);
  final Rect anchor;
  final double width;
  static const _margin = 16.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final top = anchor.bottom + 6;
    return BoxConstraints(
      maxWidth: math.min(width, constraints.maxWidth - _margin * 2),
      minWidth: math.min(width, constraints.maxWidth - _margin * 2),
      maxHeight: math.max(0, constraints.maxHeight - top - _margin),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.right - childSize.width).clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    ),
    anchor.bottom + 6,
  );

  @override
  bool shouldRelayout(_AnchoredLayout oldDelegate) =>
      anchor != oldDelegate.anchor || width != oldDelegate.width;
}
