import 'package:duanju_app/app_bottom_navigation.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/settings_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// 移动端内容区 PageView 的切换行为回归：
/// - 点按底栏 tab 平滑滑动（animateToPage）；
/// - 内容区左右划跟手切换，底栏高亮经 onPageChanged 同步；
/// - 桌面鼠标拖拽设备已纳入 dragDevices（Flutter 默认不含 mouse）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      DuanjuApp(repository: FixtureRepository(), store: store),
    );
    await tester.pumpAndSettle();
    return store;
  }

  int selectedTab(WidgetTester tester) => tester
      .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
      .selectedIndex;

  PageController pageControllerOf(WidgetTester tester) => tester
      .widget<PageView>(find.byType(PageView))
      .controller!;

  /// 沿内容区水平拖拽 [steps] 步、每步 [-60,0]（共超过半页才能吸附到下一 tab）。
  Future<void> dragLeft(WidgetTester tester, int steps) async {
    final center = tester.getCenter(find.byType(PageView));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a bottom nav tab slides the content PageView over',
      (tester) async {
    await pumpApp(tester);
    expect(selectedTab(tester), 0);
    expect(pageControllerOf(tester).page, 0.0);

    // 点「设置」：底栏高亮立即切换，PageView 以 320ms 动画滑过去。
    await tester.tap(find.byKey(const ValueKey('bottom-nav-3')));
    await tester.pump(); // 动画起点：尚未到位
    expect(selectedTab(tester), 3);
    expect(pageControllerOf(tester).page, lessThan(3.0));

    await tester.pumpAndSettle();
    expect(pageControllerOf(tester).page, 3.0);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('dragging the content area switches tabs and syncs the nav bar',
      (tester) async {
    await pumpApp(tester);

    // 左拖内容区超过半页（5×60=300px > 195px 半页）：吸附到「追剧」，底栏同步。
    await dragLeft(tester, 5);
    expect(selectedTab(tester), 1);
    expect(pageControllerOf(tester).page, 1.0);
  });

  testWidgets('a short drag springs back to the current tab', (tester) async {
    await pumpApp(tester);

    // 不足半页（3×30=90px < 195px）：弹回「发现」，底栏保持。
    final center = tester.getCenter(find.byType(PageView));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 0);
    expect(pageControllerOf(tester).page, 0.0);
  });

  testWidgets('flinging the content area switches to the adjacent tab',
      (tester) async {
    await pumpApp(tester);

    await tester.fling(
      find.byType(PageView),
      const Offset(-400, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 1);
    expect(pageControllerOf(tester).page, 1.0);
  });

  testWidgets('mouse drags are accepted by the content PageView',
      (tester) async {
    await pumpApp(tester);

    // Flutter 默认 dragDevices 不含 mouse；_PageSwipeBehavior 显式纳入，
    // 桌面（Windows / Linux）鼠标拖拽与触屏行为一致。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    final center = tester.getCenter(find.byType(PageView));
    await gesture.down(center);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedTab(tester), 1);
  });
}
