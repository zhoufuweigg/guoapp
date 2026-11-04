import 'package:duanju_app/player_controls.dart';
import 'package:duanju_app/player_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_fixtures.dart';

/// 挂载一个独立的 PlayerControls（非全屏、无侧栏弹幕、无顶栏），
/// 视口 390x300：中心播放按钮位于 y≈150，底部控制条位于底部，
/// (195, 60) 是不被任何控件遮挡的手势面区域
Future<PlayerInteractions> mountControls(
  WidgetTester tester,
  Player player,
) async {
  final interactions = PlayerInteractions(
    player: player,
    available: () => true,
    baseSpeed: () => 1.0,
    onTogglePlayback: () {},
    onFullscreen: (_) {},
    onSeek: (_) async {},
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 300,
          child: PlayerControls(
            player: player,
            interactions: interactions,
            enabled: true,
            fullscreen: false,
            showOnPlaybackReady: true,
            onFullscreen: () {},
            onBack: () {},
            onPrevious: null,
            onNext: null,
            title: '测试剧集',
            onTogglePlayback: () {},
            onEpisodes: () async {},
            onSpeed: () async {},
            onQuality: () async {},
            speed: 1.0,
            qualityLabel: '1080P',
            onFocusSurface: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return interactions;
}

double chromeOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.descendant(
      of: find.byKey(const ValueKey('player-controls-chrome')),
      matching: find.byType(AnimatedOpacity),
    ))
    .opacity;

bool chromeIgnoring(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find.byKey(const ValueKey('player-controls-chrome')),
    )
    .ignoring;

void main() {
  testWidgets('长按倍速期间自动隐藏全部控件，松手后恢复原显隐状态', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final platform = ScriptedPlayer();
    final player = Player(platformPlayer: platform);
    await platform.playOrPause();
    final interactions = await mountControls(tester, player);

    // 初始：控件可见，无倍速提示
    expect(interactions.boosting, isFalse);
    expect(chromeOpacity(tester), 1.0);
    expect(chromeIgnoring(tester), isFalse);
    expect(find.textContaining('倍速中'), findsNothing);

    // 长按超过 350ms 识别阈值，倍速开始
    final gesture = await tester.startGesture(const Offset(195, 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(interactions.boosting, isTrue);

    // 控件立即停止响应指针，并淡出
    expect(chromeIgnoring(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 250));
    expect(chromeOpacity(tester), 0.0);

    // 倍速 HUD pill（含锁定提示）不受隐藏影响，仍在显示
    expect(find.textContaining('倍速中'), findsOneWidget);

    // 倍速期间超过 4 秒自动隐藏时限，控件也不闪回
    await tester.pump(const Duration(seconds: 5));
    expect(chromeOpacity(tester), 0.0);
    expect(interactions.boosting, isTrue);

    // 松手结束倍速：恢复进入倍速前的可见状态
    await gesture.up();
    await tester.pump();
    expect(interactions.boosting, isFalse);
    await tester.pump(const Duration(milliseconds: 250));
    expect(chromeOpacity(tester), 1.0);
    expect(chromeIgnoring(tester), isFalse);

    // 烧掉恢复显隐时排定的 4 秒隐藏定时器与松手提示的 1.2 秒定时器
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('倍速前控件已隐藏时，倍速结束后保持隐藏', (tester) async {
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final platform = ScriptedPlayer();
    final player = Player(platformPlayer: platform);
    await platform.playOrPause();
    final interactions = await mountControls(tester, player);

    // 先轻点手势面隐藏控件
    // onDoubleTapDown 与 onTap 同挂：单击要等双击超时（300ms）过后才触发
    await tester.tapAt(const Offset(195, 60));
    await tester.pump(const Duration(milliseconds: 500));
    expect(chromeOpacity(tester), 0.0);

    // 隐藏状态下长按倍速
    final gesture = await tester.startGesture(const Offset(195, 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(interactions.boosting, isTrue);
    expect(chromeOpacity(tester), 0.0);
    expect(find.textContaining('倍速中'), findsOneWidget);

    // 松手后控件保持隐藏，不因倍速结束而弹出
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(interactions.boosting, isFalse);
    expect(chromeOpacity(tester), 0.0);

    // 烧掉松手提示的 1.2 秒定时器
    await tester.pump(const Duration(seconds: 3));
  });
}
