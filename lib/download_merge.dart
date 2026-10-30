import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'core_bridge.dart';
import 'media_pipeline.dart';
import 'models.dart';

String episodeRanges(List<int> numbers) {
  final parts = <String>[];
  for (var i = 0; i < numbers.length; i++) {
    final start = numbers[i];
    while (i + 1 < numbers.length && numbers[i + 1] == numbers[i] + 1) {
      i++;
    }
    parts.add(start == numbers[i] ? '$start' : '$start-${numbers[i]}');
  }
  return parts.join('、');
}

String safeFileName(String title) {
  final name = title
      .replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"/\\|?*]'), '_')
      .trim();
  return name.isEmpty ? '未命名' : name;
}

String mergeFileName(String title, List<int> numbers) {
  final ranges = episodeRanges(numbers);
  final episodes = ranges.length <= 40
      ? '第$ranges集'
      : '第${numbers.first}-${numbers.last}集等${numbers.length}集';
  return '${safeFileName(title)} $episodes.mp4';
}

String _signature(MediaProbe probe) {
  final audio = probe.streams.firstWhere(
    (stream) => stream['codec_type'] == 'audio',
    orElse: () => {},
  );
  return [
    for (final key in const [
      'codec_name',
      'profile',
      'width',
      'height',
      'pix_fmt',
      'sample_aspect_ratio',
    ])
      probe.video[key],
    for (final key in const [
      'codec_name',
      'profile',
      'sample_rate',
      'channels',
    ])
      audio[key],
  ].join('|');
}

String _concatLine(String file) {
  if (file.contains('\n') || file.contains('\r')) {
    throw AppFailure('文件路径不能包含换行');
  }
  return "file '${file.replaceAll("'", "'\\''")}'";
}

class DownloadMerge extends ChangeNotifier {
  DownloadMerge(this.repository, {MediaExecutor? executor})
    : executor = executor ?? FFmpegExecutor();

  final AppRepository repository;
  final MediaExecutor executor;
  String status = '读取分集';
  double? progress;
  String fileName = '';
  final _files = <String>[];
  double _duration = 0;
  bool _cancelled = false, _disposed = false;

  bool get cancelled => _cancelled;

  static List<String> arguments(
    String list,
    String output, {
    required bool faststart,
  }) => [
    '-f',
    'concat',
    '-safe',
    '0',
    '-i',
    list,
    '-map',
    '0:v:0',
    '-map',
    '0:a:0?',
    '-c',
    'copy',
    if (faststart) ...['-movflags', '+faststart'],
    '-f',
    'mp4',
    output,
  ];

  Future<void> prepare(List<DownloadJob> selected) async {
    final jobs = List<DownloadJob>.of(selected)
      ..sort((a, b) => a.episode.number.compareTo(b.episode.number));
    final numbers = [for (final job in jobs) job.episode.number];
    if (jobs.length < 2) throw AppFailure('至少选择 2 集');
    fileName = mergeFileName(jobs.first.drama.title, numbers);
    final groups = <String, List<int>>{};
    for (final job in jobs) {
      _check();
      final plan = await repository.localPlayback(job.drama, job.episode);
      if (plan == null || !plan.local) {
        throw AppFailure('第 ${job.episode.number} 集没有完整的本地文件');
      }
      final probe = await executor.probe(plan.url);
      _files.add(plan.url);
      _duration += probe.duration;
      (groups[_signature(probe)] ??= []).add(job.episode.number);
      progress = _files.length / jobs.length;
      _notify();
    }
    _check();
    if (groups.length > 1) {
      final ordered = groups.values.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final others = [for (final group in ordered.skip(1)) ...group]..sort();
      throw AppFailure(
        '第 ${episodeRanges(others)} 集的画面或声音格式和其余集不同，无法无损合并。'
        '请分开选择格式相同的集，或删除后重新下载这些集。',
      );
    }
  }

  Future<void> write(String output, {String? file}) async {
    _check();
    status = '合并视频';
    progress = 0;
    _notify();
    final temporary = await Directory.systemTemp.createTemp('merge');
    try {
      final list = File(path.join(temporary.path, 'concat.txt'));
      await list.writeAsString(
        'ffconcat version 1.0\n${_files.map(_concatLine).join('\n')}\n',
        flush: true,
      );
      _check();
      await executor.run(
        arguments(list.path, output, faststart: file != null),
        duration: _duration,
        progress: (value) {
          progress = value;
          _notify();
        },
      );
      if (file != null) {
        verifyMediaDuration(await executor.probe(file), _duration);
      }
    } catch (_) {
      if (file != null) {
        try {
          await File(file).delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      try {
        await temporary.delete(recursive: true);
      } catch (_) {}
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _notify();
    unawaited(executor.cancel());
  }

  void _check() {
    if (_cancelled) throw AppFailure('已取消合并');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
