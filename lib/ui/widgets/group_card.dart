import 'package:flutter/material.dart';

import 'focus_ring.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TileFocus(
      builder: (focusNode) => ListTile(
        focusNode: focusNode,
        minTileHeight: subtitle == null ? 60 : 72,
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        horizontalTitleGap: 14,
        leading: icon == null
            ? null
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: colors.onSecondaryContainer),
              ),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing:
            trailing ??
            (value == null && onTap == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      if (value case final value?)
                        Text(
                          value,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      if (onTap != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.onSurfaceVariant,
                        ),
                    ],
                  )),
        onTap: onTap,
        enabled: enabled,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 8, 0),
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (action != null)
            FocusRing(
              radius: 999,
              child: TextButton(onPressed: onAction, child: Text(action!)),
            ),
        ],
      ),
    ),
  );
}
