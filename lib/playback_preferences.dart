import 'video_enhancement_preferences.dart';

const playbackSpeeds = [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0];

enum TelevisionDecoder { optimized, hardware, software }

class PlaybackPreferences {
  const PlaybackPreferences({
    this.speed = 1,
    this.quality = 0,
    this.autoAdvance = true,
    this.danmaku = true,
    this.preload = true,
    this.enhancement = const VideoEnhancementPreferences(),
    this.televisionDecoder = TelevisionDecoder.optimized,
    this.preopen,
    this.doubleTapSeek = true,
    this.swipeLevels = true,
    this.autoPictureInPicture = false,
  });

  final double speed;
  final int quality;
  final bool autoAdvance;
  final bool danmaku;
  final bool preload;
  final VideoEnhancementPreferences enhancement;
  final TelevisionDecoder televisionDecoder;
  final bool? preopen;
  final bool doubleTapSeek;
  final bool swipeLevels;
  final bool autoPictureInPicture;

  bool preopens({required bool television}) => preopen ?? !television;

  PlaybackPreferences copyWith({
    double? speed,
    int? quality,
    bool? autoAdvance,
    bool? danmaku,
    bool? preload,
    VideoEnhancementPreferences? enhancement,
    TelevisionDecoder? televisionDecoder,
    bool? preopen,
    bool? doubleTapSeek,
    bool? swipeLevels,
    bool? autoPictureInPicture,
  }) => PlaybackPreferences(
    speed: speed ?? this.speed,
    quality: quality ?? this.quality,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    danmaku: danmaku ?? this.danmaku,
    preload: preload ?? this.preload,
    enhancement: enhancement ?? this.enhancement,
    televisionDecoder: televisionDecoder ?? this.televisionDecoder,
    preopen: preopen ?? this.preopen,
    doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
    swipeLevels: swipeLevels ?? this.swipeLevels,
    autoPictureInPicture: autoPictureInPicture ?? this.autoPictureInPicture,
  );

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'quality': quality,
    'autoAdvance': autoAdvance,
    'danmaku': danmaku,
    'preload': preload,
    'enhancement': enhancement.toJson(),
    'televisionDecoder': televisionDecoder.name,
    if (preopen != null) 'preopen': preopen,
    'doubleTapSeek': doubleTapSeek,
    'swipeLevels': swipeLevels,
    'autoPictureInPicture': autoPictureInPicture,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final speed = (value['speed'] as num? ?? 1).toDouble();
    final quality = value['quality'] as int? ?? 0;
    final autoAdvance = value['autoAdvance'] as bool? ?? true;
    final danmaku = value['danmaku'] as bool? ?? true;
    final preload = value['preload'] as bool? ?? true;
    if (!playbackSpeeds.contains(speed) || quality < 0 || quality > 4320) {
      throw const FormatException('播放偏好无效');
    }
    return PlaybackPreferences(
      speed: speed,
      quality: quality,
      autoAdvance: autoAdvance,
      danmaku: danmaku,
      preload: preload,
      enhancement: VideoEnhancementPreferences.fromJson(value['enhancement']),
      televisionDecoder:
          TelevisionDecoder.values.asNameMap()[value['televisionDecoder']] ??
          TelevisionDecoder.optimized,
      preopen: value['preopen'] as bool?,
      doubleTapSeek: value['doubleTapSeek'] as bool? ?? true,
      swipeLevels: value['swipeLevels'] as bool? ?? true,
      autoPictureInPicture: value['autoPictureInPicture'] as bool? ?? false,
    );
  }
}
