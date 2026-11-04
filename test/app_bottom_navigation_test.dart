import 'package:duanju_app/app_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<NavigationDestination>> destinations() async => const [
    NavigationDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: '发现',
    ),
    NavigationDestination(
      icon: Icon(Icons.bookmark_border_rounded),
      selectedIcon: Icon(Icons.bookmark_rounded),
      label: '追剧',
    ),
    NavigationDestination(icon: Icon(Icons.history_rounded), label: '最近观看'),
    NavigationDestination(
      icon: Icon(Icons.download_outlined),
      selectedIcon: Icon(Icons.download_rounded),
      label: '下载',
    ),
  ];

  testWidgets('悬浮底栏渲染全部图标与标签，选中项有圆形高亮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigation(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: await destinations(),
            floating: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.explore), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    for (final label in ['发现', '追剧', '最近观看', '下载']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('普通底栏同样渲染全部图标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigation(
            selectedIndex: 2,
            onDestinationSelected: (_) {},
            destinations: await destinations(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });

  testWidgets('液态玻璃底栏在着色器不可用时回退且渲染完整', (tester) async {
    // 测试环境无 Impeller，ImageFilter.shader 不可用：应走纯 Flutter 回退，
    // 图标、标签与选中项均正常渲染，不抛异常。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigation(
            selectedIndex: 1,
            onDestinationSelected: (_) {},
            destinations: await destinations(),
            floating: true,
            blurred: true,
            liquidGlass: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['发现', '追剧', '最近观看', '下载']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
