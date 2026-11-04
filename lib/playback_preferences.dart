import 'video_enhancement_preferences.dart';

const playbackSpeeds = [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0];

const videoFitTypes = ['contain', 'cover', 'fill', 'fitWidth', 'fitHeight'];

const fitTypeLabels = <String, String>{
  'contain': '自动',
  'cover': '裁剪',
  'fill': '拉伸',
  'fitWidth': '等宽',
  'fitHeight': '等高',
};

const fitTypeEntries = <({String key, String label})>[
  (key: 'contain', label: '自动'),
  (key: 'cover', label: '裁剪'),
  (key: 'fill', label: '拉伸'),
  (key: 'fitWidth', label: '等宽'),
  (key: 'fitHeight', label: '等高'),
];

/// 横滑拖动进度时，一屏对应的秒数选项（PiliNara sliderDuration）
const dragSeekSteps = [15, 30, 60, 90, 120];

class PlaybackPreferences {
  const PlaybackPreferences({
    this.speed = 1,
    this.quality = 0,
    this.autoAdvance = true,
    this.danmaku = true,
    this.preload = true,
    this.enhancement = const VideoEnhancementPreferences(),
    this.fitType = 'contain',
    this.slideVolumeBrightness = true,
    this.slideFullscreen = true,
    this.quickDoubleTap = false,
    this.doubleTapSeekSeconds = 10,
    this.dragSeekSeconds = 60,
    this.longPressSpeed = 3.0,
    this.autoLongPressSpeed = false,
    this.keepSpeedLockAcrossEpisodes = true,
    this.saveCatalogProgress = true,
    this.gestureSchema = 2,
  });

  final double speed;
  final int quality;
  final bool autoAdvance;
  final bool danmaku;
  final bool preload;
  final VideoEnhancementPreferences enhancement;

  /// 画面比例：contain 自动 / cover 裁剪 / fill 拉伸 / fitWidth 等宽 / fitHeight 等高
  final String fitType;

  /// 滑动调节音量与亮度
  final bool slideVolumeBrightness;

  /// 中部竖向滑动切换全屏
  final bool slideFullscreen;

  /// 双击左/右区域快退/快进；关闭后双击任意位置均为播放/暂停（PiliNara 的 enableQuickDouble=false 行为）
  final bool quickDoubleTap;

  /// 双击快进快退秒数
  final int doubleTapSeekSeconds;

  /// 横向拖动进度时，拖动一屏对应的秒数（PiliNara sliderDuration）
  final int dragSeekSeconds;

  /// 长按倍速
  final double longPressSpeed;

  /// 长按自动倍速（当前速度 ×2）
  final bool autoLongPressSpeed;

  /// 切换剧集时保持倍速锁定：true 继续以锁定的倍速播放；false 解除锁定并恢复正常倍速
  final bool keepSpeedLockAcrossEpisodes;

  /// 保存各站源、各分类目录的浏览断点，再次进入时从断点继续
  final bool saveCatalogProgress;

  /// 手势配置版本：v1（旧默认）→ v2（双击=播放/暂停、横滑限幅）
  final int gestureSchema;

  PlaybackPreferences copyWith({
    double? speed,
    int? quality,
    bool? autoAdvance,
    bool? danmaku,
    bool? preload,
    VideoEnhancementPreferences? enhancement,
    String? fitType,
    bool? slideVolumeBrightness,
    bool? slideFullscreen,
    bool? quickDoubleTap,
    int? doubleTapSeekSeconds,
    int? dragSeekSeconds,
    double? longPressSpeed,
    bool? autoLongPressSpeed,
    bool? keepSpeedLockAcrossEpisodes,
    bool? saveCatalogProgress,
    int? gestureSchema,
  }) => PlaybackPreferences(
    speed: speed ?? this.speed,
    quality: quality ?? this.quality,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    danmaku: danmaku ?? this.danmaku,
    preload: preload ?? this.preload,
    enhancement: enhancement ?? this.enhancement,
    fitType: fitType ?? this.fitType,
    slideVolumeBrightness: slideVolumeBrightness ?? this.slideVolumeBrightness,
    slideFullscreen: slideFullscreen ?? this.slideFullscreen,
    quickDoubleTap: quickDoubleTap ?? this.quickDoubleTap,
    doubleTapSeekSeconds: doubleTapSeekSeconds ?? this.doubleTapSeekSeconds,
    dragSeekSeconds: dragSeekSeconds ?? this.dragSeekSeconds,
    longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    autoLongPressSpeed: autoLongPressSpeed ?? this.autoLongPressSpeed,
    keepSpeedLockAcrossEpisodes:
        keepSpeedLockAcrossEpisodes ?? this.keepSpeedLockAcrossEpisodes,
    saveCatalogProgress: saveCatalogProgress ?? this.saveCatalogProgress,
    gestureSchema: gestureSchema ?? this.gestureSchema,
  );

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'quality': quality,
    'autoAdvance': autoAdvance,
    'danmaku': danmaku,
    'preload': preload,
    'enhancement': enhancement.toJson(),
    'fitType': fitType,
    'slideVolumeBrightness': slideVolumeBrightness,
    'slideFullscreen': slideFullscreen,
    'quickDoubleTap': quickDoubleTap,
    'doubleTapSeekSeconds': doubleTapSeekSeconds,
    'dragSeekSeconds': dragSeekSeconds,
    'longPressSpeed': longPressSpeed,
    'autoLongPressSpeed': autoLongPressSpeed,
    'keepSpeedLockAcrossEpisodes': keepSpeedLockAcrossEpisodes,
    'saveCatalogProgress': saveCatalogProgress,
    'gestureSchema': gestureSchema,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final speed = (value['speed'] as num? ?? 1).toDouble();
    final quality = value['quality'] as int? ?? 0;
    final autoAdvance = value['autoAdvance'] as bool? ?? true;
    final danmaku = value['danmaku'] as bool? ?? true;
    final preload = value['preload'] as bool? ?? true;
    final fitType = value['fitType'] as String? ?? 'contain';
    final slideVolumeBrightness =
        value['slideVolumeBrightness'] as bool? ?? true;
    final slideFullscreen = value['slideFullscreen'] as bool? ?? true;
    final longPressSpeed = (value['longPressSpeed'] as num? ?? 3.0).toDouble();
    final autoLongPressSpeed = value['autoLongPressSpeed'] as bool? ?? false;
    final keepSpeedLockAcrossEpisodes =
        value['keepSpeedLockAcrossEpisodes'] as bool? ?? true;
    final saveCatalogProgress = value['saveCatalogProgress'] as bool? ?? true;
    // 旧版手势配置（无 gestureSchema）迁移到 v2 默认：双击=播放/暂停、横滑一屏 60 秒
    final migrated = (value['gestureSchema'] as int? ?? 1) < 2;
    final quickDoubleTap = migrated
        ? false
        : (value['quickDoubleTap'] as bool? ?? false);
    final doubleTapSeekSeconds = (value['doubleTapSeekSeconds'] as int? ?? 10)
        .clamp(5, 60);
    final dragSeekSeconds = migrated
        ? 60
        : (value['dragSeekSeconds'] as int? ?? 60).clamp(15, 300);
    if (!playbackSpeeds.contains(speed) || quality < 0 || quality > 4320) {
      throw const FormatException('播放偏好无效');
    }
    if (!videoFitTypes.contains(fitType)) {
      throw const FormatException('播放偏好无效');
    }
    return PlaybackPreferences(
      speed: speed,
      quality: quality,
      autoAdvance: autoAdvance,
      danmaku: danmaku,
      preload: preload,
      enhancement: VideoEnhancementPreferences.fromJson(value['enhancement']),
      fitType: fitType,
      slideVolumeBrightness: slideVolumeBrightness,
      slideFullscreen: slideFullscreen,
      quickDoubleTap: quickDoubleTap,
      doubleTapSeekSeconds: doubleTapSeekSeconds,
      dragSeekSeconds: dragSeekSeconds,
      longPressSpeed: longPressSpeed,
      autoLongPressSpeed: autoLongPressSpeed,
      keepSpeedLockAcrossEpisodes: keepSpeedLockAcrossEpisodes,
      saveCatalogProgress: saveCatalogProgress,
      gestureSchema: 2,
    );
  }
}
