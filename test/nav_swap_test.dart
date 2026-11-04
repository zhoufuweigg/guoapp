import 'package:duanju_app/app_bottom_navigation.dart';
import 'package:duanju_app/downloads_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings is a first-class bottom nav tab and downloads moved '
      'into the overflow menu', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final repository = FixtureRepository();
    await tester.pumpWidget(
      DuanjuApp(repository: repository, store: store),
    );
    await tester.pumpAndSettle();

    // 底栏最右侧是「设置」而非「下载」。
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('下载'), findsNothing);

    // 点底栏「设置」直接切入设置 tab 内容区（一级页面，非 push 路由）。
    await tester.tap(find.byKey(const ValueKey('bottom-nav-3')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .selectedIndex,
      3,
    );

    // 一级页面：无左上返回按钮，设置项直接呈现。
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('设备互联'), findsOneWidget);

    // 点底栏「追剧」切回，底栏选中态跟随。
    await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .selectedIndex,
      1,
    );

    // 「下载」仍在右上角三点菜单，点它推下载页。
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('下载'), findsOneWidget);
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);
  });
}
