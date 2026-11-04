import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'app_layout.dart';
import 'widgets.dart';

enum SwipeAction { none, brightness, volume, fullscreen, horizontal }

enum SpeedLockHint {
  none,
  swipeUpToLock,
  releaseToLock,
  lockedConfirm,
  swipeDownToUnlock,
  releaseToUnlock,
  unlockedConfirm,
}

class GestureHudState {
  const GestureHudState({
    this.type = SwipeAction.none,
    this.value = 0.0,
    this.seekTarget = Duration.zero,
    this.seekDelta = 0,
    this.cancelSeek = false,
  });

  final SwipeAction type;
  final double value; // 0.0 ~ 1.0
  final Duration seekTarget;
  final int seekDelta;
  final bool cancelSeek;

  bool get isSeek => type == SwipeAction.horizontal;
  bool get isBrightness => type == SwipeAction.brightness;
  bool get isVolume => type == SwipeAction.volume;
}

class PlayerGestureOptions {
  const PlayerGestureOptions({
    this.slideVolumeBrightness = true,
    this.slideFullscreen = true,
    this.quickDoubleTap = false,
    this.doubleTapSeekSeconds = 10,
    this.dragSeekSeconds = 60,
    this.longPressSpeed = 3.0,
    this.autoLongPressSpeed = false,
    this.keepSpeedLockAcrossEpisodes = true,
  });

  final bool slideVolumeBrightness;
  final bool slideFullscreen;
  final bool quickDoubleTap;
  final int doubleTapSeekSeconds;

  /// 横向拖动进度时，拖动一屏对应的秒数（PiliNara sliderDuration，默认 60）
  final int dragSeekSeconds;
  final double longPressSpeed;
  final bool autoLongPressSpeed;

  /// 切换剧集时保持倍速锁定：true 继续以锁定的倍速播放；false 解除锁定并恢复正常倍速
  final bool keepSpeedLockAcrossEpisodes;

  PlayerGestureOptions copyWith({
    bool? slideVolumeBrightness,
    bool? slideFullscreen,
    bool? quickDoubleTap,
    int? doubleTapSeekSeconds,
    int? dragSeekSeconds,
    double? longPressSpeed,
    bool? autoLongPressSpeed,
    bool? keepSpeedLockAcrossEpisodes,
  }) => PlayerGestureOptions(
    slideVolumeBrightness: slideVolumeBrightness ?? this.slideVolumeBrightness,
    slideFullscreen: slideFullscreen ?? this.slideFullscreen,
    quickDoubleTap: quickDoubleTap ?? this.quickDoubleTap,
    doubleTapSeekSeconds: doubleTapSeekSeconds ?? this.doubleTapSeekSeconds,
    dragSeekSeconds: dragSeekSeconds ?? this.dragSeekSeconds,
    longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    autoLongPressSpeed: autoLongPressSpeed ?? this.autoLongPressSpeed,
    keepSpeedLockAcrossEpisodes:
        keepSpeedLockAcrossEpisodes ?? this.keepSpeedLockAcrossEpisodes,
  );
}

class PlayerInteractions extends ChangeNotifier {
  PlayerInteractions({
    required this.player,
    required this.available,
    required this.baseSpeed,
    required this.onTogglePlayback,
    required this.onFullscreen,
    required this.onSeek,
    this.options = const PlayerGestureOptions(),
    this.onEpisode,
    VoidCallback? onControlsToggle,
  }) : _onControlsToggle = onControlsToggle {
    _playing = player.stream.playing.listen((playing) {
      if (!playing) cancel();
    });
    AppDevice.getBrightness().then((val) {
      if (!_disposed) {
        _brightness = val;
        notifyListeners();
      }
    }).catchError((_) {});
    // Android：音量映射到系统媒体音量（AudioManager STREAM_MUSIC），与
    // PiliNara 默认手势行为一致；读取失败保持 null，回退播放器内部音量
    AppDevice.getSystemVolume().then((val) {
      if (_disposed || val == null) return;
      _deviceVolume = val;
      // libmpv 内部音量保持满值，系统音量作为唯一衰减环节，
      // 避免「内部 × 系统」双重衰减导致最大音量偏小
      unawaited(player.setVolume(100));
      notifyListeners();
    }).catchError((_) {});
  }

  final Player player;
  final bool Function() available;
  final double Function() baseSpeed;
  final VoidCallback onTogglePlayback;

  /// 请求切换全屏：true 进入全屏，false 退出全屏（PiliNara 中部竖向滑动分方向语义）
  final ValueChanged<bool> onFullscreen;
  final Future<void> Function(Duration) onSeek;
  final String Function(int direction)? onEpisode;
  final VoidCallback? _onControlsToggle;
  PlayerGestureOptions options;

  late final StreamSubscription<bool> _playing;
  Timer? _holdTimer;
  Timer? _hintTimer;
  Timer? _hudTimer;
  Timer? _lockHintTimer;
  Future<void> _rates = Future<void>.value();
  final Set<int> _pointers = {};
  int? _pointer;
  Offset? _origin;
  Offset? _lastPosition;
  bool _swipeEnabled = false;
  bool _moved = false;
  bool _held = false;
  bool _boosting = false;
  bool _keyboardHold = false;
  bool _cancelUntilRelease = false;
  bool _disposed = false;
  double _unmutedVolume = 100;
  String _feedback = '';
  DateTime _ignoreTapUntil = DateTime(2000);
  SwipeAction _swipeAction = SwipeAction.none;
  GestureHudState _hudState = const GestureHudState();
  double _brightness = 0.5;
  double _initialBrightness = 0.5;
  double _viewWidth = 0.0;
  double _viewHeight = 0.0;
  double _lastSeekDx = 0.0;
  bool _fullscreenTriggered = false;

  /// Android 设备音量缓存（0..1）：非 Android 平台或系统音量不可用时为
  /// null，此时音量回退到 libmpv 播放器内部音量
  double? _deviceVolume;

  /// 音量手势起点快照（0..1）：平台系统音量与 media_kit 的 state.volume
  /// 均经异步回填，逐帧读取会滞后于实际设置，导致 HUD 显示漂移
  double _initialVolume = 1.0;

  /// 亮度手势代数：手势结束后回读平台亮度时，若已开始新手势则丢弃
  int _brightnessGestureId = 0;

  bool _hasToasted = false;

  bool _speedLocked = false;
  bool _speedLockArmed = false;
  SpeedLockHint _speedLockHint = SpeedLockHint.none;
  Offset? _longPressOrigin;

  /// 倍速锁定时实际使用的倍速（切换剧集后按需恢复）
  double? _lockedSpeed;

  GestureHudState get hudState => _hudState;

  /// 当前全屏状态（由界面同步），键盘 F/F11 与手势共用
  bool fullscreen = false;
  double get brightness => _brightness;
  bool get isBrightnessActive => _hudState.type == SwipeAction.brightness;
  String get feedback => _feedback;
  bool get boosting => _boosting;
  bool get speedLocked => _speedLocked;
  SpeedLockHint get speedLockHint => _speedLockHint;
  bool get suppressTap => DateTime.now().isBefore(_ignoreTapUntil);
  Future<void> get pendingRates => _rates;

  void updateOptions(PlayerGestureOptions value) {
    options = value;
  }

  void setBrightnessDirect(double value) {
    if (_disposed) return;
    _brightness = value.clamp(0.01, 1.0);
    AppDevice.setBrightness(_brightness);
    _showHud(SwipeAction.brightness, _brightness);
  }

  /// 当前音量（0..1）：Android 取系统媒体音量，其他平台取播放器内部音量
  double get volume => _deviceVolume ?? player.state.volume / 100;

  /// 应用音量（0..1）：设备模式下写系统音量并刷新缓存，否则写 libmpv 内部音量
  void _applyVolume(double value) {
    final target = value.clamp(0.0, 1.0);
    if (_deviceVolume != null) {
      _deviceVolume = target;
      notifyListeners();
      unawaited(AppDevice.setSystemVolume(target));
      return;
    }
    unawaited(player.setVolume(target * 100));
  }

  /// 音量面板直接设置（0..1）：面板自带百分比显示，不走 hint 反馈
  void setVolumeFraction(double fraction) {
    if (!available()) return;
    _applyVolume(fraction);
    if (fraction > 0) _unmutedVolume = fraction * 100;
  }

  void dismissBrightnessHud() {
    _scheduleDismissHud();
  }

  void hint(String message, {bool persistent = false}) {
    if (_disposed) return;
    _hintTimer?.cancel();
    if (_feedback != message) {
      _feedback = message;
      notifyListeners();
    }
    if (!persistent && message.isNotEmpty) {
      _hintTimer = Timer(const Duration(milliseconds: 1200), () {
        hint(
          _boosting && !_speedLocked
              ? '${_currentBoostSpeed()} 倍速 · 松开恢复'
              : '',
          persistent: true,
        );
      });
    }
  }

  Future<void> applySpeed() => _setRate(baseSpeed());

  double _currentBoostSpeed() {
    if (options.autoLongPressSpeed) return baseSpeed() * 2;
    return options.longPressSpeed;
  }

  Future<void> _setRate(double value) {
    _rates = _rates
        .catchError((Object _) {})
        .then((_) => player.setRate(value));
    unawaited(
      _rates.catchError((Object _) {
        hint('倍速调整失败，请重试');
      }),
    );
    return _rates;
  }

  void _beginHold() {
    if (!available() || _holdTimer != null || _boosting) return;
    _holdTimer = Timer(const Duration(milliseconds: 350), () {
      _holdTimer = null;
      if (_disposed ||
          !available() ||
          !player.state.playing ||
          player.state.completed) {
        return;
      }
      _held = true;
      _longPressOrigin = _lastPosition;
      _speedLockArmed = false;
      HapticFeedback.lightImpact();
      if (_speedLocked) {
        // 锁定态长按不得再调速：setRate 会覆盖已锁定的倍速
        // （自动倍速下还会二次翻倍），仅提示下滑解锁
        _boosting = true;
        _speedLockHint = SpeedLockHint.swipeDownToUnlock;
        notifyListeners();
        return;
      }
      _boosting = true;
      unawaited(_setRate(_currentBoostSpeed()));
      _speedLockHint = SpeedLockHint.swipeUpToLock;
      notifyListeners();
      hint('${_currentBoostSpeed()} 倍速 · 上滑可锁定', persistent: true);
    });
  }

  void _endHold({bool tap = false, bool silent = false}) {
    final wasKeyboard = _keyboardHold;
    final boosted = _boosting;
    _holdTimer?.cancel();
    _holdTimer = null;
    _keyboardHold = false;
    _boosting = false;
    _longPressOrigin = null;
    final commit = _speedLockArmed;
    _speedLockArmed = false;
    if (_speedLocked) {
      if (commit) {
        _speedLocked = false;
        HapticFeedback.mediumImpact();
        unawaited(_setRate(baseSpeed()));
        _showTransientLockHint(SpeedLockHint.unlockedConfirm);
      } else {
        _speedLockHint = SpeedLockHint.none;
        notifyListeners();
      }
      // 清掉长按期间可能残留的提示文案，避免松手后滞留屏幕
      hint('');
    } else if (boosted) {
      if (commit) {
        _speedLocked = true;
        // 记录锁定时的实际倍速，供切换剧集后按设置恢复
        _lockedSpeed = _currentBoostSpeed();
        HapticFeedback.mediumImpact();
        _showTransientLockHint(SpeedLockHint.lockedConfirm);
        // 清掉长按开始时「上滑可锁定」的常驻文案，避免锁定后滞留屏幕
        hint('');
      } else {
        _speedLockHint = SpeedLockHint.none;
        notifyListeners();
        unawaited(_setRate(baseSpeed()));
        if (!silent) hint('恢复 ${baseSpeed()} 倍速');
      }
    }
    if (!boosted && tap && wasKeyboard) {
      seek(5);
    }
  }

  void releaseSpeedLock() {
    if (!_speedLocked) return;
    _speedLocked = false;
    _speedLockArmed = false;
    _lockedSpeed = null;
    _cancelLockHintTimer();
    _speedLockHint = SpeedLockHint.none;
    notifyListeners();
    unawaited(_setRate(baseSpeed()));
  }

  /// 切换剧集后的倍速应用。
  ///
  /// 锁定态下按 [PlayerGestureOptions.keepSpeedLockAcrossEpisodes] 决定：
  /// - true：继续以锁定的倍速播放（如长按锁定的 2 倍）
  /// - false：解除锁定并恢复正常倍速（未加速前的播放速度）
  ///
  /// 未锁定时一律恢复正常倍速。切换剧集会重新 open 媒体，
  /// 播放器倍速被重置，因此这里必须在 open 完成后重新设置。
  Future<void> applySpeedAfterEpisodeSwitch() {
    if (_speedLocked && options.keepSpeedLockAcrossEpisodes) {
      return _setRate(_lockedSpeed ?? _currentBoostSpeed());
    }
    if (_speedLocked) {
      _speedLocked = false;
      _speedLockArmed = false;
      _lockedSpeed = null;
      _cancelLockHintTimer();
      _speedLockHint = SpeedLockHint.none;
      notifyListeners();
    }
    return _setRate(baseSpeed());
  }

  void _showTransientLockHint(SpeedLockHint value) {
    _speedLockHint = value;
    notifyListeners();
    _lockHintTimer?.cancel();
    _lockHintTimer = Timer(const Duration(seconds: 2), () {
      if (_speedLockHint == value) {
        _speedLockHint = SpeedLockHint.none;
        notifyListeners();
      }
    });
  }

  void _cancelLockHintTimer() {
    _lockHintTimer?.cancel();
    _lockHintTimer = null;
  }

  void onLongPressMove(Offset localPosition) {
    if (!_boosting || _longPressOrigin == null || _viewHeight <= 0) return;
    final dy = localPosition.dy - _longPressOrigin!.dy;
    final threshold = (_viewHeight * 0.22).clamp(48.0, 112.0);
    if (_speedLocked) {
      if (!_speedLockArmed && dy >= threshold) {
        _speedLockArmed = true;
        HapticFeedback.lightImpact();
        _speedLockHint = SpeedLockHint.releaseToUnlock;
        notifyListeners();
      } else if (_speedLockArmed && dy <= threshold - 10) {
        _speedLockArmed = false;
        HapticFeedback.lightImpact();
        _speedLockHint = SpeedLockHint.swipeDownToUnlock;
        notifyListeners();
      }
    } else {
      if (!_speedLockArmed && dy <= -threshold) {
        _speedLockArmed = true;
        HapticFeedback.lightImpact();
        _speedLockHint = SpeedLockHint.releaseToLock;
        notifyListeners();
      } else if (_speedLockArmed && dy >= -(threshold - 10)) {
        _speedLockArmed = false;
        HapticFeedback.lightImpact();
        _speedLockHint = SpeedLockHint.swipeUpToLock;
        notifyListeners();
      }
    }
  }

  void cancel() {
    if (_disposed) return;
    if (_pointers.isNotEmpty) {
      _cancelUntilRelease = true;
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    _pointer = null;
    _origin = null;
    _lastPosition = null;
    _longPressOrigin = null;
    _endHold(silent: true);
    _hudState = const GestureHudState();
    hint('');
    notifyListeners();
  }

  void pointerDown(
    PointerDownEvent event, {
    required bool swipeEnabled,
    double width = 0.0,
    required double height,
  }) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1 || _cancelUntilRelease) {
      cancel();
      return;
    }
    if (!available() || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _origin = _lastPosition = event.localPosition;
    _swipeEnabled = swipeEnabled && event.kind == PointerDeviceKind.touch;
    _viewWidth = width;
    _viewHeight = height;
    _moved = _held = false;
    _swipeAction = SwipeAction.none;
    _hasToasted = false;
    _lastSeekDx = 0.0;
    _fullscreenTriggered = false;
    _brightnessGestureId++;

    _beginHold();
  }

  void pointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer || _origin == null) return;
    _lastPosition = event.localPosition;
    final diff = event.localPosition - _origin!;
    if (diff.distance > 12) {
      _moved = true;
      if (_boosting) {
        // 长按倍速中：指针移动只服务于倍速锁定/解锁手势，不结束
        // 倍速、不触发音量/亮度/进度滑动（PiliNara 中长按识别器
        // 独占指针，滑动分区同样不生效）
        onLongPressMove(event.localPosition);
        return;
      }
      _endHold();
      onLongPressMove(event.localPosition);
    }
    if (!_swipeEnabled || !_moved || _viewHeight <= 0) return;

    final dx = diff.dx;
    final dy = diff.dy;

    if (_swipeAction == SwipeAction.none) {
      if (dx.abs() > dy.abs() * 3 && dx.abs() > 12) {
        if (player.state.duration <= Duration.zero) return;
        _swipeAction = SwipeAction.horizontal;
        _showSeekHud();
      } else if (dy.abs() > dx.abs() * 3 && dy.abs() > 12) {
        if (!options.slideVolumeBrightness && !options.slideFullscreen) {
          return;
        }
        final sectionWidth = _viewWidth / 3;
        if (event.localPosition.dx < sectionWidth) {
          if (!options.slideVolumeBrightness) return;
          _swipeAction = SwipeAction.brightness;
          // 同步以缓存亮度为基准：异步平台读取若晚于首批移动事件到达，
          // 会用陈旧值覆盖手势已应用的实际亮度，造成显示与实际错位
          // （PiliNara 在手势期间同样忽略平台亮度回调）
          _initialBrightness = _brightness;
          _showHud(SwipeAction.brightness, _brightness);
        } else if (event.localPosition.dx < sectionWidth * 2) {
          if (!options.slideFullscreen) return;
          _swipeAction = SwipeAction.fullscreen;
        } else {
          if (!options.slideVolumeBrightness) return;
          _swipeAction = SwipeAction.volume;
          // 手势起点快照音量，移动中以此本地基准推算，避免异步流滞后
          _initialVolume = volume;
          _showHud(SwipeAction.volume, _initialVolume);
        }
      }
      return;
    }

    switch (_swipeAction) {
      case SwipeAction.horizontal:
        final topZone = _viewHeight * 0.125;
        final inCancelZone =
            event.localPosition.dy <= topZone &&
            (event.localPosition.dx >= _viewWidth * 0.875 ||
                event.localPosition.dx <= _viewWidth * 0.125);
        if (inCancelZone) {
          if (!_hasToasted) {
            _hasToasted = true;
            _hudState = const GestureHudState(
              type: SwipeAction.horizontal,
              cancelSeek: true,
            );
            notifyListeners();
          }
          return;
        }
        if (_hasToasted) {
          _hasToasted = false;
          _showSeekHud();
        }
        _updateSeekHud(dx);
      case SwipeAction.brightness:
        final level = _viewHeight * 3;
        final value = (_initialBrightness - dy / level).clamp(0.0, 1.0);
        AppDevice.setBrightness(value);
        _brightness = value;
        _showHud(SwipeAction.brightness, value);
      case SwipeAction.volume:
        // 以手势起点音量为基准本地推算（0..1），避免异步流滞后；
        // Android 下映射系统媒体音量，其他平台映射 libmpv 内部音量
        final value =
            (_initialVolume - dy / (_viewHeight * 0.5)).clamp(0.0, 1.0);
        _applyVolume(value);
        _showHud(SwipeAction.volume, value);
      case SwipeAction.fullscreen:
        // PiliNara 语义：中部上滑进入全屏、下滑退出全屏；触发后 latch，不再重复
        if (_fullscreenTriggered) break;
        const threshold = 2.5;
        final cumulative = event.localPosition.dy - _origin!.dy;
        if (cumulative > threshold) {
          _fullscreenTriggered = true;
          onFullscreen(false);
          _ignoreTapUntil = DateTime.now().add(
            const Duration(milliseconds: 600),
          );
        } else if (cumulative < -threshold) {
          _fullscreenTriggered = true;
          onFullscreen(true);
          _ignoreTapUntil = DateTime.now().add(
            const Duration(milliseconds: 600),
          );
        }
      case SwipeAction.none:
        break;
    }
  }

  Duration? _seekToPos;

  void _updateSeekHud(double dx) {
    final durationMs = player.state.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final curPos =
        _seekToPos?.inMilliseconds ?? player.state.position.inMilliseconds;
    // PiliNara 语义：posDelta = sliderScale * 增量dx / 屏宽，默认拖满一屏 = dragSeekSeconds 秒
    final incremental = dx - _lastSeekDx;
    _lastSeekDx = dx;
    final posDelta =
        (options.dragSeekSeconds * 1000 * incremental / _viewWidth).round();
    final newPos = (curPos + posDelta).clamp(0, durationMs);
    _seekToPos = Duration(milliseconds: newPos);
    _showSeekHud();
  }

  void _showSeekHud() {
    final durationMs = player.state.duration.inMilliseconds;
    final target = _seekToPos ?? player.state.position;
    final delta = ((target.inMilliseconds - player.state.position.inMilliseconds) / 1000).round();
    _hudState = GestureHudState(
      type: SwipeAction.horizontal,
      seekTarget: target,
      seekDelta: delta,
      value: durationMs > 0 ? target.inMilliseconds / durationMs : 0,
    );
    notifyListeners();
  }

  void pointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_cancelUntilRelease) {
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
      if (_pointers.isEmpty) _cancelUntilRelease = false;
      return;
    }
    if (_pointer != event.pointer || _origin == null) return;

    if (_swipeAction == SwipeAction.horizontal) {
      final target = _seekToPos;
      _seekToPos = null;
      if (target != null && !_hasToasted) {
        unawaited(onSeek(target));
        hint('${target.inSeconds > player.state.position.inSeconds ? '快进至' : '后退至'} ${formatPosition(target.inSeconds.toDouble())}');
      }
      _hudState = const GestureHudState();
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 200));
    } else if (_swipeAction == SwipeAction.brightness ||
        _swipeAction == SwipeAction.volume) {
      _scheduleDismissHud();
    }

    if (_swipeAction == SwipeAction.brightness) {
      // 手势结束后回读平台实际亮度（平台会把下限钳到 0.01），让缓存与
      // 真实值一致；若期间已开始新手势（代数变化）则丢弃本次回读
      final gestureId = _brightnessGestureId;
      AppDevice.getBrightness().then((val) {
        if (!_disposed && gestureId == _brightnessGestureId) {
          _brightness = val.clamp(0.01, 1.0);
        }
      }).catchError((_) {});
    }

    if (_moved || _held) {
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    _pointer = null;
    _origin = null;
    _endHold();
  }

  void pointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    cancel();
    _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    if (_pointers.isEmpty) _cancelUntilRelease = false;
  }

  void _showHud(SwipeAction action, double value) {
    if (_disposed) return;
    _hudTimer?.cancel();
    _hudState = GestureHudState(type: action, value: value);
    notifyListeners();
  }

  void _scheduleDismissHud() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_disposed) return;
      _hudState = const GestureHudState();
      notifyListeners();
    });
  }

  void seek(int seconds) {
    if (!available() || player.state.duration <= Duration.zero) return;
    _endHold();
    final target = (player.state.position.inMilliseconds + seconds * 1000)
        .clamp(0, player.state.duration.inMilliseconds);
    unawaited(onSeek(Duration(milliseconds: target)));
    hint('${seconds > 0 ? '快进至' : '后退至'} ${formatPosition(target / 1000)}');
  }

  void doubleTapSeek(bool forward) {
    if (!available() || player.state.duration <= Duration.zero) return;
    final seconds = options.doubleTapSeekSeconds;
    seek(forward ? seconds : -seconds);
  }

  void changeVolume(double delta) {
    if (!available()) return;
    final current = volume * 100;
    final next = (current + delta).clamp(0.0, 100.0);
    _applyVolume(next / 100);
    if (next > 0) _unmutedVolume = next;
    hint(next == 0 ? '已静音' : '音量 ${next.round()}%');
  }

  void toggleMute() {
    if (!available()) return;
    final current = volume * 100;
    if (current > 0) _unmutedVolume = current;
    final target = current > 0 ? 0.0 : _unmutedVolume;
    _applyVolume(target / 100);
    hint(target == 0 ? '已静音' : '音量 ${target.round()}%');
  }

  void toggleControls() {
    _onControlsToggle?.call();
  }

  KeyEventResult key(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowRight && _keyboardHold) {
        _endHold(tap: available());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    if (hardware.isAltPressed ||
        hardware.isMetaPressed ||
        hardware.isShiftPressed) {
      cancel();
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      if (event is KeyDownEvent) {
        cancel();
        onFullscreen(!fullscreen);
      }
      return KeyEventResult.handled;
    }
    if (hardware.isControlPressed || !available()) {
      return KeyEventResult.ignored;
    }
    if (key != LogicalKeyboardKey.arrowRight) _endHold();
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) {
        _keyboardHold = true;
        _beginHold();
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      seek(-5);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      changeVolume(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      changeVolume(-5);
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyDownEvent) onTogglePlayback();
    } else if (key == LogicalKeyboardKey.keyM) {
      if (event is KeyDownEvent) toggleMute();
    } else if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (event is KeyDownEvent) {
        final handler = onEpisode;
        if (handler != null) {
          hint(handler(key == LogicalKeyboardKey.mediaTrackNext ? 1 : -1));
        }
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _disposed = true;
    _holdTimer?.cancel();
    _hintTimer?.cancel();
    _hudTimer?.cancel();
    _lockHintTimer?.cancel();
    AppDevice.resetBrightness();
    if (_boosting || _speedLocked) unawaited(_setRate(baseSpeed()));
    _boosting = false;
    _speedLocked = false;
    _speedLockArmed = false;
    _lockedSpeed = null;
    _playing.cancel();
    _pointers.clear();
    super.dispose();
  }
}
