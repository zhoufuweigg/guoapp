import 'package:duanju_app/theme_appearance.dart';
import 'package:duanju_app/theme_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duanju_app/theme_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('外观偏好可持久化并做边界收敛', () async {
    SharedPreferences.setMockInitialValues({});
    final store = testStore(await SharedPreferences.getInstance());
    expect(store.themeAppearance.scale, 1);
    expect(store.themeAppearance.blurBars, isFalse);

    await store.setThemeAppearance(
      const ThemeAppearance(
        blurBars: true,
        floatingBar: true,
        liquidGlass: true,
        swipeBack: true,
        scale: 1.25,
      ),
    );
    final saved = store.themeAppearance;
    expect(saved.blurBars, isTrue);
    expect(saved.floatingBar, isTrue);
    expect(saved.liquidGlass, isTrue);
    expect(saved.swipeBack, isTrue);
    expect(saved.scale, 1.25);

    // 越界值必须被收敛到允许区间。
    final clamped = ThemeAppearance.fromJson({
      'scale': 9.0,
      'blurBars': true,
    });
    expect(clamped.scale, ThemeAppearance.maxScale);
    expect(clamped.floatingBar, isFalse);

    // 损坏的配置不应抛错，回退默认值。
    SharedPreferences.setMockInitialValues({'themeAppearance': '{broken'});
    final restored = testStore(await SharedPreferences.getInstance());
    expect(restored.themeAppearance.scale, 1);
    restored.dispose();
    store.dispose();
  });

  test('反序列化归一化液态玻璃与悬浮底栏的不变量', () {
    final restored = ThemeAppearance.fromJson(const {
      'floatingBar': false,
      'liquidGlass': true,
    });
    expect(restored.floatingBar, isFalse);
    expect(restored.liquidGlass, isFalse, reason: '液态玻璃依赖悬浮底栏，非法组合应被归一化');
  });

  testWidgets('主题设置页渲染全部开关', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = testStore(await SharedPreferences.getInstance());
    // 拉高视口，保证分组卡片全部进入可查找范围。
    tester.view.physicalSize = const Size(400, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ThemeSettingsScreen(store: store)),
    );
    await tester.pumpAndSettle();

    for (final label in [
      '主题',
      '模糊',
      '悬浮底栏',
      '液态玻璃',
      '预测性返回手势',
      '横移返回手势',
      '界面缩放',
    ]) {
      expect(find.text(label), findsOneWidget, reason: "缺少设置项：$label");
    }
    expect(find.text('100%'), findsOneWidget);
    store.dispose();
  });
}
