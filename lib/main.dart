import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_device.dart';
import 'core_bridge.dart';
import 'diary_service.dart';
import 'local_store.dart';
import 'picture_in_picture.dart';
import 'ui/app.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(AppTheme.systemBars(Brightness.dark));
  }
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    try {
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(1280, 800),
          minimumSize: desktopMinimumSize,
          center: true,
        ),
        () async => windowManager.show(),
      );
    } catch (_) {}
  }
  MediaKit.ensureInitialized();
  final device = await AppDevice.detect();
  final rendering = Platform.isAndroid
      ? ', 渲染: ${await AppDevice.compatibleRendering() ? 'skia' : 'impeller'}'
      : '';
  DiaryService.add(
    '[App] 应用启动，版本: ${device.version}, '
    '平台: ${Platform.operatingSystem}$rendering',
  );
  runApp(AppBootstrap(device: device));
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.device = const AppDevice()});
  final AppDevice device;
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  final repository = NativeRepository();
  LocalStore? store;
  Object? error;
  late AppDevice device = widget.device;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      unawaited(_refreshDevice());
    }
    if (!Platform.isIOS) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        NativeRepository(
          background: true,
        ).controlDownloads('pauseAll').catchError((Object _) {}),
      );
    }
  }

  Future<void> _refreshDevice() async {
    final detected = await AppDevice.detect(fallback: device);
    if (!mounted ||
        (device.television == detected.television &&
            device.version == detected.version)) {
      return;
    }
    setState(() => device = detected);
  }

  Future<void> _initialize() async {
    setState(() => error = null);
    try {
      final preferences = await SharedPreferences.getInstance();
      await _refreshDevice();
      await repository.initialize();
      if (!mounted) return;
      setState(() {
        final local = store = LocalStore(preferences);
        repository.access = local;
      });
    } catch (failure) {
      if (mounted) setState(() => error = failure);
    }
  }

  @override
  Widget build(BuildContext context) => DuanjuApp(
    repository: repository,
    store: store,
    bootstrapError: error?.toString(),
    onRetry: _initialize,
    television: device.television,
    version: device.version,
  );
}
