import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/source_gate_dialog.dart';
import 'package:duanju_app/source_gate_taps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 输入框光标闪烁会让动画不收敛，固定光标保证 pump 步进可预期。
  EditableText.debugDeterministicCursor = true;

  Future<LocalStore> create([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(Map.of(initial));
    final store = testStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  test('default visibility shows every compiled source', () async {
    final store = await create();
    expect(store.sourceGateEnabled, isFalse);
    expect(store.sourcesUnlocked, isTrue);
    expect(
      store.sources.map((site) => site.id),
      allSourcesEnabled
          ? [
              'hongguo',
              'hanxiaoquan',
              'guipian',
              'sorani',
              'huangdou',
              'huangju',
              'yeguo',
              'dsd',
              'huangguo-video',
              'huangguoai',
              'cloudfront',
            ]
          : ['hongguo'],
    );
    expect(store.allowsSource('huangdou'), allSourcesEnabled);
    expect(store.allowsSource('hongguo'), isTrue);
    // 未启用密码锁时敏感站源打开即用，无需任何解锁操作。
    expect(store.sourceGateEnabled, isFalse);
    await expectLater(store.unlockSources('666'), throwsStateError);
    expect(store.sourcesUnlocked, isTrue);
  });

  test('enabling the gate hides restricted sources and unlocks once', () async {
    final store = await create();
    await store.enableSourceGate('666');
    expect(store.sourceGateEnabled, isTrue);
    expect(store.sourcesUnlocked, isTrue);
    expect(store.sources.length, allSourcesEnabled ? 11 : 1);

    store.lockSources();
    expect(store.sourcesUnlocked, isFalse);
    expect(store.sources.length, allSourcesEnabled ? 4 : 1);
    expect(store.allowsSource('huangdou'), isFalse);
    expect(store.allowsSource('hongguo'), isTrue);
    if (allSourcesEnabled) expect(store.allowsSource('sorani'), isTrue);

    await expectLater(store.unlockSources('777'), throwsStateError);
    expect(store.sourcesUnlocked, isFalse);
    await store.unlockSources('666');
    expect(store.sourcesUnlocked, isTrue);
    expect(store.sources.length, allSourcesEnabled ? 11 : 1);
  });

  test('a saved gate hides sources again after restart', () async {
    final store = await create();
    await store.enableSourceGate('666');
    store.lockSources();
    final restarted = testStore(store.preferences);
    addTearDown(restarted.dispose);
    expect(restarted.sourceGateEnabled, isTrue);
    expect(restarted.sourcesUnlocked, isFalse);
    expect(restarted.sources.length, allSourcesEnabled ? 4 : 1);
    await restarted.unlockSources('666');
    expect(restarted.sourcesUnlocked, isTrue);
  });

  test('disabling the gate restores every compiled source', () async {
    final store = await create();
    await store.enableSourceGate('666');
    store.lockSources();
    await store.disableSourceGate();
    expect(store.sourceGateEnabled, isFalse);
    expect(store.sourcesUnlocked, isTrue);
    expect(store.sources.length, allSourcesEnabled ? 11 : 1);
  });

  test('an invalid pin must be 3 to 12 digits', () async {
    final store = await create();
    await expectLater(store.enableSourceGate('12'), throwsStateError);
    await expectLater(store.enableSourceGate('abcdef'), throwsStateError);
    await expectLater(
      store.enableSourceGate('1234567890123'),
      throwsStateError,
    );
    expect(store.sourceGateEnabled, isFalse);
  });

  test('repeated taps on one entry only fire after six in a row', () {
    final gate = RepeatTapGate();
    for (var i = 0; i < 5; i++) {
      expect(gate.register(2), isFalse);
    }
    expect(gate.register(2), isTrue);
    expect(gate.register(2), isFalse);
    gate.reset();
    for (var i = 0; i < 5; i++) {
      expect(gate.register(2), isFalse);
    }
    // 切换入口会清零计数，避免误触发。
    expect(gate.register(0), isFalse);
    for (var i = 0; i < 5; i++) {
      expect(gate.register(2), isFalse);
    }
    expect(gate.register(2), isTrue);
  });

  test('a damaged gate record keeps hiding restricted sources', () async {
    final store = await create({
      'sourceGateEnabled': true,
      'sourceGateSalt': 'bad',
      'sourceGateHash': 'bad',
    });
    expect(store.configurationError, isNull);
    expect(store.sourceGateEnabled, isFalse);
    expect(store.sourcesUnlocked, isFalse);
    expect(store.sources.length, allSourcesEnabled ? 4 : 1);
  });

  test('a user-disabled gate keeps every compiled source visible', () async {
    final store = await create({
      'sourceGateEnabled': false,
      'sourceGateOff': true,
    });
    expect(store.sourceGateEnabled, isFalse);
    expect(store.sourcesUnlocked, isTrue);
    expect(store.sources.length, allSourcesEnabled ? 11 : 1);
  });

  // 密码锁弹窗含动画与异步回调，用固定步进代替 pumpAndSettle，
  // 避免不收敛的动画让测试挂到 10 分钟默认超时。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('the gate dialog offers enabling, unlocking and locking', (
    tester,
  ) async {
    final store = await create();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSourceGateDialog(context, store),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    // 未启用时给用户「启用密码锁」的选择。
    await tester.tap(find.text('打开'));
    await settle(tester);
    expect(find.text('站源密码锁'), findsOneWidget);
    expect(find.text('启用密码锁'), findsOneWidget);
    expect(find.text('解锁'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '666');
    await tester.enterText(find.byType(TextField).last, '666');
    await tester.tap(find.text('启用密码锁'));
    await settle(tester);
    expect(store.sourceGateEnabled, isTrue);
    expect(store.sourcesUnlocked, isTrue);

    // 已启用且已解锁时提供「重新锁定」与「关闭密码功能」。
    await tester.tap(find.text('打开'));
    await settle(tester);
    expect(find.text('重新锁定'), findsOneWidget);
    expect(find.text('关闭密码功能'), findsOneWidget);
    await tester.tap(find.text('重新锁定'));
    await settle(tester);
    expect(store.sourcesUnlocked, isFalse);

    // 锁定后要求输入密码才能解锁。
    await tester.tap(find.text('打开'));
    await settle(tester);
    expect(find.text('解锁'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '666');
    await tester.tap(find.text('解锁'));
    await settle(tester);
    expect(store.sourcesUnlocked, isTrue);

    // 仍可关闭密码功能，恢复全部站源可见。
    await tester.tap(find.text('打开'));
    await settle(tester);
    await tester.tap(find.text('关闭密码功能'));
    await settle(tester);
    expect(store.sourceGateEnabled, isFalse);
    expect(store.sourcesUnlocked, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
