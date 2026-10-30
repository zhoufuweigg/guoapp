import 'package:flutter/material.dart';

import '../../local_store.dart';
import '../../theme_color.dart';
import '../app_scope.dart';
import '../widgets/focus_ring.dart';
import '../widgets/group_card.dart';
import 'settings_rows.dart';

const themeModes = {'light': '浅色', 'dark': '深色', 'system': '跟随系统'};

const displayModes = {
  'auto': '自动识别设备',
  'television': '电视',
  'phone': '手机',
  'pad': '平板',
  'window': '窗口',
};

Map<String, String> get availableDisplayModes => {
  for (final MapEntry(:key, :value) in displayModes.entries)
    if (desktopPlatform || key != 'window') key: value,
};

String platformDisplayMode(String mode) =>
    mode == 'window' && !desktopPlatform ? 'pad' : mode;

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key, required this.store});
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final systemColorAvailable = AppScope.of(context).systemColorAvailable;
    final following = systemColorAvailable && store.followSystemColor;
    return Column(
      spacing: 12,
      children: [
        GroupCard(
          children: [
            SettingsTile(
              title: '主题模式',
              subtitle: themeModes[store.themeMode] ?? themeModes['system']!,
              onTap: () async {
                final selection = await showOptionDialog(
                  context,
                  title: '主题模式',
                  options: themeModes,
                  selected: store.themeMode,
                );
                if (selection != null && context.mounted) {
                  await saveSetting(
                    context,
                    () => store.setThemeMode(selection),
                  );
                }
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            TileFocus(
              builder: (focusNode) => SwitchListTile(
                focusNode: focusNode,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('跟随系统取色'),
                subtitle: Text(
                  systemColorAvailable
                      ? 'Android 12 及以上跟随壁纸，Windows 跟随系统强调色'
                      : '本机不支持系统取色，使用预设色板',
                ),
                value: following,
                onChanged: systemColorAvailable
                    ? (value) => saveSetting(
                        context,
                        () => store.setFollowSystemColor(value),
                      )
                    : null,
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            Opacity(
              opacity: following ? 0.45 : 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text('预设色板', style: text.titleMedium),
                        Text(
                          following ? '关闭「跟随系统取色」后可选' : '选一个种子色生成整套配色',
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        for (final color in ThemeColor.values)
                          Expanded(
                            child: _Swatch(
                              color: color,
                              selected: !following && store.themeColor == color,
                              onPressed: following
                                  ? null
                                  : () => saveSetting(
                                      context,
                                      () => store.setThemeColor(color),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        GroupCard(
          children: [
            SettingsTile(
              title: '界面模式',
              subtitle: displayModes[platformDisplayMode(store.displayMode)]!,
              onTap: () async {
                final selection = await showOptionDialog(
                  context,
                  title: '界面模式',
                  options: availableDisplayModes,
                  selected: platformDisplayMode(store.displayMode),
                );
                if (selection != null && context.mounted) {
                  await saveSetting(
                    context,
                    () => store.setDisplayMode(selection),
                  );
                }
              },
            ),
            if (AppScope.of(context).television) ...[
              const Divider(indent: 16, endIndent: 16),
              SwitchTile(
                title: '搜索用字母键盘',
                subtitle: '开启后按确认键弹出字母键盘，可按拼音首字母搜；关闭时使用系统输入法',
                value: store.televisionKeyboard,
                onChanged: (value) => saveSetting(
                  context,
                  () => store.setTelevisionKeyboard(value),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onPressed,
  });
  final ThemeColor color;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(color.seed),
      brightness: theme.brightness,
    );
    return Column(
      spacing: 6,
      children: [
        Semantics(
          button: true,
          selected: selected,
          label: color.label,
          excludeSemantics: true,
          child: FocusRing(
            radius: 999,
            child: Container(
              width: 50,
              height: 50,
              padding: const EdgeInsets.all(3),
              decoration: ShapeDecoration(
                shape: CircleBorder(
                  side: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Material(
                color: scheme.primary,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: selected
                      ? Icon(Icons.check_rounded, color: scheme.onPrimary)
                      : null,
                ),
              ),
            ),
          ),
        ),
        Text(
          color.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
