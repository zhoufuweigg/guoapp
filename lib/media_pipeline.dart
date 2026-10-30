import 'dart:async';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

import 'core_bridge.dart';

class MediaProbe {
  MediaProbe(this.raw);
  final Map<String, dynamic> raw;
  List<Map<String, dynamic>> get streams => (raw['streams'] as List? ?? [])
      .whereType<Map>()
      .map((s) => Map<String, dynamic>.from(s))
      .toList();
  Map<String, dynamic> get video =>
      streams.firstWhere((s) => s['codec_type'] == 'video', orElse: () => {});
  double get duration =>
      double.tryParse('${(raw['format'] as Map?)?['duration']}') ?? 0;
  String get videoCodec => video['codec_name'] as String? ?? '';
}

abstract class MediaExecutor {
  Future<MediaProbe> probe(String file);
  Future<void> run(
    List<String> arguments, {
    double duration = 0,
    void Function(double)? progress,
  });
  Future<void> cancel();
}

class FFmpegExecutor implements MediaExecutor {
  int? _session;
  bool _cancelled = false;

  @override
  Future<MediaProbe> probe(String file) async {
    final session = await FFprobeKit.getMediaInformationFromCommandArguments([
      '-v',
      'error',
      '-hide_banner',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      '-protocol_whitelist',
      'file,crypto,data',
      '-i',
      file,
    ]);
    final data = session.getMediaInformation()?.getAllProperties();
    if (data == null) throw AppFailure('无法读取本地视频信息，请检查文件完整性。');
    return MediaProbe(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> run(
    List<String> arguments, {
    double duration = 0,
    void Function(double)? progress,
  }) async {
    _cancelled = false;
    final finished = Completer<AppFailure?>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      [
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-y',
        '-protocol_whitelist',
        'file,crypto,data',
        ...arguments,
      ],
      (result) async {
        try {
          final code = await result.getReturnCode();
          if (finished.isCompleted) return;
          finished.complete(
            ReturnCode.isSuccess(code)
                ? null
                : AppFailure(
                    _cancelled || ReturnCode.isCancel(code)
                        ? '已取消本地媒体处理'
                        : '本地媒体处理失败（${code?.getValue() ?? -1}），原分集已保留。',
                  ),
          );
        } catch (_) {
          if (!finished.isCompleted) {
            finished.complete(AppFailure('无法读取媒体处理结果，原分集已保留。'));
          }
        }
      },
      null,
      (statistics) {
        if (duration > 0) {
          progress?.call((statistics.getTime() / 1000 / duration).clamp(0, 1));
        }
      },
    );
    _session = session.getSessionId();
    try {
      if (_cancelled) await FFmpegKit.cancel(_session);
      final failure = await finished.future;
      if (failure != null) throw failure;
    } finally {
      _session = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    if (_session != null) await FFmpegKit.cancel(_session);
  }
}

void verifyMediaDuration(MediaProbe probe, double expected) {
  if (probe.videoCodec.isEmpty ||
      !probe.duration.isFinite ||
      probe.duration <= 0 ||
      expected > 0 &&
          (probe.duration - expected).abs() > max(2, expected * .02)) {
    throw AppFailure('生成的视频时长或视频轨不完整，原分集已保留。');
  }
}
