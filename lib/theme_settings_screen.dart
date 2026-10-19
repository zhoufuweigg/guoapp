import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'local_store.dart';
import 'theme_appearance.dart';

/// 主题设置：flutter_miuix（HyperOS 风格）组件，按分组卡片排布。
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
  final _snackbar = MiuixSnackbarHostState();
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
      _snackbar.showSnackbar('外观设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseTheme(int index) async {
    try {
      await widget.store.setThemeMode(_themeModes[index]);
    } catch (_) {
      _snackbar.showSnackbar('主题设置保存失败，请重试');
    }
  }

  Widget _card(List<Widget> rows) => MiuixCard(
        insideMargin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(children: rows),
      );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final modeIndex = _themeModes.indexOf(widget.store.themeMode).clamp(
              0,
              _themeModes.length - 1,
            );
        return MiuixTheme(
          data: brightness == Brightness.dark
              ? MiuixThemeData.dark()
              : MiuixThemeData.light(),
          // MiuixScaffold 不提供 Material 祖先：缺失时其内部 Text 会回退到
          // 带黄色下划线的默认样式（Flutter 无 Material 兜底），必须显式包一层。
          child: Material(
            type: MaterialType.transparency,
            child: MiuixScaffold(
              snackbarHost: MiuixSnackbarHost(state: _snackbar),
              topBar: MiuixTopAppBar(
                title: '主题设置',
                largeTitle: '主题设置',
                navigationIcon: MiuixIconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Icon(Icons.arrow_back_rounded, size: 22),
                ),
              ),
              content: (padding) => ListView(
                padding: padding.copyWith(
                  left: 16,
                  right: 16,
                  top: 4,
                  bottom: 28,
                ),
                children: [
                  const MiuixSmallTitle(
                    '外观',
                    insideMargin: EdgeInsets.fromLTRB(12, 10, 12, 8),
                  ),
                  _card([
                    MiuixOverlayDropdownPreference(
                      title: '主题',
                      summary: '选择应用的主题模式',
                      items: _themeLabels,
                      selectedIndex: modeIndex,
                      onSelectedIndexChange: _chooseTheme,
                    ),
                    const MiuixHorizontalDivider(),
                    MiuixSwitchPreference(
                      title: '模糊',
                      summary: '启用顶栏和底栏的模糊效果',
                      value: _appearance.blurBars,
                      enabled: !_saving,
                      onChanged: (value) => _update(
                        _appearance.copyWith(
                          blurBars: value,
                          floatingBar: value ? _appearance.floatingBar : false,
                        ),
                      ),
                    ),
                  ]),
                  const MiuixSmallTitle(
                    '底栏样式',
                    insideMargin: EdgeInsets.fromLTRB(12, 16, 12, 8),
                  ),
                  _card([
                    MiuixSwitchPreference(
                      title: '悬浮底栏',
                      summary: '使用类 Apple 风格的悬浮底栏',
                      value: _appearance.floatingBar,
                      enabled: !_saving,
                      onChanged: (value) => _update(
                        _appearance.copyWith(
                          floatingBar: value,
                          liquidGlass: value ? _appearance.liquidGlass : false,
                        ),
                      ),
                    ),
                    const MiuixHorizontalDivider(),
                    MiuixSwitchPreference(
                      title: '液态玻璃',
                      summary: '启用悬浮底栏的液态玻璃效果',
                      value: _appearance.liquidGlass,
                      enabled: !_saving,
                      onChanged: (value) => _update(
                        _appearance.copyWith(
                          liquidGlass: value,
                          floatingBar: value ? true : _appearance.floatingBar,
                        ),
                      ),
                    ),
                  ]),
                  const MiuixSmallTitle(
                    '手势',
                    insideMargin: EdgeInsets.fromLTRB(12, 16, 12, 8),
                  ),
                  _card([
                    MiuixSwitchPreference(
                      title: '预测性返回手势',
                      summary: '启用对预测性返回手势的支持',
                      value: _appearance.predictiveBack,
                      enabled: !_saving,
                      onChanged: (value) => _update(
                        _appearance.copyWith(predictiveBack: value),
                      ),
                    ),
                    const MiuixHorizontalDivider(),
                    MiuixSwitchPreference(
                      title: '横移返回手势',
                      summary: '从屏幕边缘横移返回上一页',
                      value: _appearance.swipeBack,
                      enabled: !_saving,
                      onChanged: (value) =>
                          _update(_appearance.copyWith(swipeBack: value)),
                    ),
                  ]),
                  const MiuixSmallTitle(
                    '显示',
                    insideMargin: EdgeInsets.fromLTRB(12, 16, 12, 8),
                  ),
                  _card([
                    MiuixSliderPreference(
                      title: '界面缩放',
                      summary: '调整全局显示比例',
                      value: _appearance.scale,
                      min: ThemeAppearance.minScale,
                      max: ThemeAppearance.maxScale,
                      steps: 9,
                      valueText: '${(_appearance.scale * 100).round()}%',
                      onValueChange: (value) => setState(() {
                        _appearance = _appearance.copyWith(
                          scale: (value * 100).roundToDouble() / 100,
                        );
                      }),
                      onValueChangeFinished: () =>
                          _update(_appearance, notify: false),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
