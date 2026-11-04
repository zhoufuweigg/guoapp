import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'downloads_test.dart';

Future<LocalStore> makeStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  addTearDown(store.dispose);
  return store;
}

void size(WidgetTester tester, Size value) {
  tester.view.physicalSize = value;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tick(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets('页面被覆盖时 store 通知不触发首页重建，返回后恢复刷新', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = DownloadRepository();
    final store = await makeStore();
    size(tester, const Size(400, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(repository: repository, store: store),
      ),
    );
    await tick(tester);

    final before = identityHashCode(tester.widget(find.byType(Scaffold).first));

    // 压栈覆盖页后，store 通知不应导致首页 Scaffold 被重建（实例不变）。
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    final popped = navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const _BlankCover()),
    );
    await tick(tester);
    await store.setThemeMode('dark');
    await tick(tester);
    final covered = identityHashCode(
      tester.widget(find.byType(Scaffold).first),
    );
    expect(covered, before, reason: '后台期间首页不应重建');

    // 返回前台后通知应恢复生效（实例被重建替换）。
    navigator.pop();
    await tick(tester);
    await store.setThemeMode('system');
    await tick(tester);
    final restored = identityHashCode(
      tester.widget(find.byType(Scaffold).first),
    );
    expect(restored, isNot(before), reason: '回前台后首页应恢复响应 store 通知');

    await popped;
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
  });
}

class _BlankCover extends StatelessWidget {
  const _BlankCover();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.teal, child: SizedBox.expand());
}
