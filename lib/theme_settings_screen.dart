import 'package:flutter/material.dart';

import 'local_store.dart';
import 'theme_appearance.dart';

/// 主题设置：标准 Material 风格，按分组列表排布。
class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  static const _themeModes = ['system', 'light', 'dark'];
  static const _themeLabels = ['跟随系统', '浅色', '深色'];

  late ThemeAppearance _appearance = widget.store.themeAppearance;
  bool _saving = false;

  Future<void> _update(
    ThemeAppearance next, {
    bool persist = true,
    bool notify = true,
  }) async {
    if (notify) setState(() => _appearance = next);
    if (!persist) return;
    setState(() => _saving = true);
    try {
      await widget.store.setThemeAppearance(next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('外观设置保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseTheme(int index) async {
    try {
      await widget.store.setThemeMode(_themeModes[index]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('主题设置保存失败，请重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final modeIndex = _themeModes.indexOf(widget.store.themeMode).clamp(
            0,
            _themeModes.length - 1,
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('外观'),
                  const SizedBox(height: 8),
                  // 主题三选：常驻可点的分段按钮，无需弹层。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('主题'),
                        for (var index = 0; index < _themeModes.length; index++)
                          ChoiceChip(
                            key: ValueKey('theme-mode-${_themeModes[index]}'),
                            label: Text(_themeLabels[index]),
                            selected: index == modeIndex,
                            onSelected: _saving
                                ? null
                                : (_) => _chooseTheme(index),
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile.adaptive(
                    key: const ValueKey('theme-blur'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('模糊'),
                    subtitle: const Text('启用顶栏和底栏的模糊效果'),
                    value: _appearance.blurBars,
                    onChanged: _saving
                        ? null
                        : (value) => _update(
                            _appearance.copyWith(
                              blurBars: value,
                              floatingBar: value
                                  ? _appearance.floatingBar
                                  : false,
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  const Text('底栏样式'),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    key: const ValueKey('theme-floating-bar'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('悬浮底栏'),
                    subtitle: const Text('使用类 Apple 风格的悬浮底栏'),
                    value: _appearance.floatingBar,
                    onChanged: _saving
                        ? null
                        : (value) => _update(
                            _appearance.copyWith(
                              floatingBar: value,
                              liquidGlass: value
                                  ? _appearance.liquidGlass
                                  : false,
                            ),
                          ),
                  ),
                  SwitchListTile.adaptive(
                    key: const ValueKey('theme-liquid-glass'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('液态玻璃'),
                    subtitle: const Text('启用悬浮底栏的液态玻璃效果'),
                    value: _appearance.liquidGlass,
                    onChanged: _saving
                        ? null
                        : (value) => _update(
                            _appearance.copyWith(
                              liquidGlass: value,
                              floatingBar: value
                                  ? true
                                  : _appearance.floatingBar,
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  const Text('手势'),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    key: const ValueKey('theme-predictive-back'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('预测性返回手势'),
                    subtitle: const Text('启用对预测性返回手势的支持'),
                    value: _appearance.predictiveBack,
                    onChanged: _saving
                        ? null
                        : (value) => _update(
                            _appearance.copyWith(predictiveBack: value),
                          ),
                  ),
                  SwitchListTile.adaptive(
                    key: const ValueKey('theme-swipe-back'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('横移返回手势'),
                    subtitle: const Text('从屏幕边缘横移返回上一页'),
                    value: _appearance.swipeBack,
                    onChanged: _saving
                        ? null
                        : (value) =>
                            _update(_appearance.copyWith(swipeBack: value)),
                  ),
                  const SizedBox(height: 20),
                  const Text('显示'),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('界面缩放'),
                        Text('${(_appearance.scale * 100).round()}%'),
                      ],
                    ),
                  ),
                  Slider.adaptive(
                    value: _appearance.scale,
                    min: ThemeAppearance.minScale,
                    max: ThemeAppearance.maxScale,
                    divisions: 9,
                    onChanged: (value) => setState(() {
                      _appearance = _appearance.copyWith(
                        scale: (value * 100).roundToDouble() / 100,
                      );
                    }),
                    onChangeEnd: (_) => _update(_appearance, notify: false),
                  ),
                  const Text(
                    '调整全局显示比例，松开手指后保存',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
