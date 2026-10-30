import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app_device.dart';

typedef MiniWindowFrame = ({double left, double top, double extent});

const desktopMinimumSize = Size(960, 640);
const _miniExtent = 480.0;

double _clampRatio(double aspectRatio) =>
    aspectRatio.isFinite && aspectRatio > 0
    ? aspectRatio.clamp(1 / 2.39, 2.39)
    : 16 / 9;

Map<String, int> _ratio(double aspectRatio) {
  final ratio = _clampRatio(aspectRatio);
  return ratio >= 1
      ? {'width': (1000 * ratio).round(), 'height': 1000}
      : {'width': 1000, 'height': (1000 / ratio).round()};
}

Size _miniSize(double ratio, double extent) =>
    ratio >= 1 ? Size(extent, extent / ratio) : Size(extent * ratio, extent);

class PictureInPicture extends ChangeNotifier {
  PictureInPicture._() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    AppDevice.channel.setMethodCallHandler(_handle);
    AppLifecycleListener(onStateChange: _lifecycleChanged);
    unawaited(_status());
  }

  static final instance = PictureInPicture._();

  void Function(String action)? onAction;
  bool _supported = false;
  bool _active = false;
  bool _pending = false;
  bool _leaving = false;
  bool _window = false;
  bool _autoEnter = false;
  double? _windowRatio;
  Timer? _timer;
  Map<String, Object>? _sent;
  ({Rect bounds, bool maximized, bool fullScreen})? _macRestore;

  bool get available => switch (defaultTargetPlatform) {
    TargetPlatform.android => _supported,
    TargetPlatform.windows || TargetPlatform.macOS => true,
    _ => false,
  };

  bool get shown => _active || _pending || _window;
  bool get leaving => _leaving;
  bool get window => _window;

  bool keepsPlaying(AppLifecycleState? state) =>
      _active ||
      state == AppLifecycleState.inactive &&
          (_pending || _leaving || _autoEnter);

  Future<void> _status() async {
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'pictureInPictureStatus',
      );
      _supported = status?['supported'] == true;
    } catch (_) {
      _supported = false;
    }
    notifyListeners();
  }

  Future<void> _handle(MethodCall call) async {
    final arguments = call.arguments;
    switch (call.method) {
      case 'pictureInPictureChanged':
        _setActive(arguments is Map && arguments['active'] == true);
      case 'pictureInPicturePending':
        _pending = true;
        notifyListeners();
      case 'pictureInPictureAction':
        if (arguments case {'action': final String action}) {
          onAction?.call(action);
        }
    }
  }

  void _setActive(bool active) {
    _timer?.cancel();
    _leaving = _active && !active;
    _active = active;
    _pending = false;
    if (_leaving) {
      _timer = Timer(const Duration(milliseconds: 700), () {
        _leaving = false;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void _lifecycleChanged(AppLifecycleState state) {
    if (!_pending || state == AppLifecycleState.inactive) return;
    _pending = false;
    notifyListeners();
  }

  void update({
    required double aspectRatio,
    required bool playing,
    required bool hasPrevious,
    required bool hasNext,
    required bool autoEnter,
  }) {
    if (defaultTargetPlatform != TargetPlatform.android || !_supported) return;
    _autoEnter = autoEnter;
    final next = <String, Object>{
      ..._ratio(aspectRatio),
      'playing': playing,
      'hasPrevious': hasPrevious,
      'hasNext': hasNext,
      'autoEnter': autoEnter,
    };
    if (mapEquals(next, _sent)) return;
    _sent = next;
    unawaited(
      AppDevice.channel
          .invokeMethod<void>('updatePictureInPicture', next)
          .catchError((Object _) {}),
    );
  }

  void clear() {
    _autoEnter = false;
    if (_sent == null) return;
    _sent = null;
    unawaited(
      AppDevice.channel
          .invokeMethod<void>('updatePictureInPicture')
          .catchError((Object _) {}),
    );
  }

  Future<void> enter(double aspectRatio, {MiniWindowFrame? frame}) async {
    if (shown || !available) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _enterSystem(aspectRatio);
    }
    final ratio = _clampRatio(aspectRatio);
    _window = true;
    _windowRatio = ratio;
    notifyListeners();
    await WidgetsBinding.instance.endOfFrame;
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        await AppDevice.channel.invokeMethod<void>('setMiniWindow', {
          'enabled': true,
          'aspect': ratio,
          if (frame != null) ...{
            'left': frame.left.round(),
            'top': frame.top.round(),
            'extent': frame.extent.round(),
          },
        });
      } else {
        await _enterMac(ratio, frame);
      }
    } catch (_) {
      _window = false;
      notifyListeners();
    }
  }

  Future<void> _enterSystem(double aspectRatio) async {
    _timer?.cancel();
    _pending = true;
    notifyListeners();
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'enterPictureInPicture',
        _ratio(aspectRatio),
      );
      if (status?['active'] == true || status?['requested'] == true) {
        if (_pending) {
          _timer = Timer(const Duration(seconds: 2), () {
            if (!_pending) return;
            _pending = false;
            notifyListeners();
          });
        }
        return;
      }
    } catch (_) {}
    _pending = false;
    notifyListeners();
  }

  Future<void> _enterMac(double ratio, MiniWindowFrame? frame) async {
    final fullScreen = await windowManager.isFullScreen();
    if (fullScreen) {
      await windowManager.setFullScreen(false);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    final maximized = await windowManager.isMaximized();
    _macRestore = (
      bounds: await windowManager.getBounds(),
      maximized: maximized,
      fullScreen: fullScreen,
    );
    if (maximized) await windowManager.unmaximize();
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setMinimumSize(const Size(120, 120));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setAspectRatio(ratio);
    final size = _miniSize(ratio, frame?.extent ?? _miniExtent);
    if (frame != null) {
      await windowManager.setBounds(
        Rect.fromLTWH(frame.left, frame.top, size.width, size.height),
      );
    } else {
      await windowManager.setSize(size);
      await windowManager.setAlignment(Alignment.bottomRight);
    }
  }

  void resize(double aspectRatio) {
    final ratio = _clampRatio(aspectRatio);
    if (!_window || ratio == _windowRatio) return;
    _windowRatio = ratio;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(
        AppDevice.channel
            .invokeMethod<void>('setMiniWindow', {
              'enabled': true,
              'aspect': ratio,
            })
            .catchError((Object _) {}),
      );
      return;
    }
    unawaited(() async {
      try {
        final size = await windowManager.getSize();
        await windowManager.setAspectRatio(ratio);
        await windowManager.setSize(
          _miniSize(ratio, math.max(size.width, size.height)),
        );
      } catch (_) {}
    }());
  }

  Future<MiniWindowFrame?> exit() async {
    if (!_window) return null;
    MiniWindowFrame? frame;
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final values = await AppDevice.channel.invokeMapMethod<String, dynamic>(
          'setMiniWindow',
          {'enabled': false},
        );
        if (values case {
          'left': final int left,
          'top': final int top,
          'extent': final int extent,
        }) {
          frame = (
            left: left.toDouble(),
            top: top.toDouble(),
            extent: extent.toDouble(),
          );
        }
      } else {
        frame = await _exitMac();
      }
    } catch (_) {}
    await WidgetsBinding.instance.endOfFrame;
    _window = false;
    _windowRatio = null;
    notifyListeners();
    return frame;
  }

  Future<MiniWindowFrame> _exitMac() async {
    final bounds = await windowManager.getBounds();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setAspectRatio(0);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(desktopMinimumSize);
    if (_macRestore case final restore?) {
      await windowManager.setBounds(restore.bounds);
      if (restore.maximized) await windowManager.maximize();
      if (restore.fullScreen) await windowManager.setFullScreen(true);
    }
    _macRestore = null;
    return (
      left: bounds.left,
      top: bounds.top,
      extent: math.max(bounds.width, bounds.height),
    );
  }
}
