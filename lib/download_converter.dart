import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

import 'core_bridge.dart';
import 'diary_service.dart';
import 'download_export.dart';
import 'download_overview.dart';
import 'media_pipeline.dart';
import 'models.dart';

class DownloadConverter extends ChangeNotifier {
  DownloadConverter(this.repository, this.downloads, {MediaExecutor? executor})
    : executor = executor ?? FFmpegExecutor() {
    downloads.addListener(_sync);
    if (Platform.isIOS) {
      _lifecycle = AppLifecycleListener(onPause: _suspend, onResume: _resume);
    }
    _sync();
  }

  final AppRepository repository;
  final DownloadOverview downloads;
  final MediaExecutor executor;
  AppLifecycleListener? _lifecycle;
  final _skipped = <String>{};
  String? _current;
  double? _progress;
  bool _cancelled = false, _suspended = false, _disposed = false;

  double? progressOf(String id) => id == _current ? _progress : null;

  static List<String> arguments(DownloadConversion work) => [
    if (work.key.isNotEmpty) ...['-decryption_key', work.key],
    if (path.extension(work.input).toLowerCase() == '.m3u8') ...[
      '-allowed_extensions',
      'ALL',
      '-extension_picky',
      '0',
    ],
    '-i',
    work.input,
    '-map',
    '0:v:0',
    '-map',
    '0:a:0?',
    '-c',
    'copy',
    '-movflags',
    '+faststart',
    work.output,
  ];

  void _sync() {
    _skipped.removeWhere(
      (id) => !downloads.jobs.any((job) => job.id == id && job.converting),
    );
    final current = _current;
    if (current != null) {
      if (!downloads.jobs.any((job) => job.id == current && job.converting)) {
        _cancel();
      }
      return;
    }
    if (_suspended || _disposed) return;
    DownloadJob? next;
    for (final job in downloads.jobs) {
      if (!job.converting || _skipped.contains(job.id)) continue;
      if (next == null ||
          job.created < next.created ||
          job.created == next.created &&
              job.episode.number < next.episode.number) {
        next = job;
      }
    }
    if (next != null) unawaited(_convert(next));
  }

  Future<void> _convert(DownloadJob job) async {
    _current = job.id;
    _progress = 0;
    _cancelled = false;
    notifyListeners();
    var result = 'cancel';
    try {
      final DownloadConversion work;
      try {
        work = await repository.beginConversion(job.id);
      } catch (_) {
        _skipped.add(job.id);
        rethrow;
      }
      if (_cancelled) return;
      final duration = await _duration(work.input);
      if (_cancelled) return;
      result = 'failed';
      await executor.run(
        arguments(work),
        duration: duration,
        progress: (value) {
          _progress = value;
          if (!_disposed) notifyListeners();
        },
      );
      verifyMediaDuration(await executor.probe(work.output), duration);
      result = 'done';
    } catch (error) {
      if (_cancelled) {
        result = 'cancel';
      } else if (result == 'failed') {
        DiaryService.add(
          '[下载] ${job.drama.title} 第 ${job.episode.number} 集转换失败：$error',
        );
      }
    } finally {
      try {
        await repository.finishConversion(job.id, result);
      } catch (_) {}
      _current = null;
      _progress = null;
      if (!_disposed) {
        notifyListeners();
        await downloads.refresh();
        _sync();
      }
    }
    if (result == 'done') await _export(job);
  }

  Future<void> _export(DownloadJob job) async {
    if (!Platform.isAndroid || !downloads.store.autoExport || _disposed) return;
    try {
      await exportDownload(
        repository,
        job,
        delete: downloads.store.deleteAfterAutoExport,
      );
    } catch (error) {
      DiaryService.add(
        '[下载] ${job.drama.title} 第 ${job.episode.number} 集导出失败：$error',
      );
    }
    if (!_disposed) await downloads.refresh();
  }

  Future<double> _duration(String input) async {
    try {
      return (await executor.probe(input)).duration;
    } catch (_) {
      return 0;
    }
  }

  void _cancel() {
    if (_current == null || _cancelled) return;
    _cancelled = true;
    unawaited(executor.cancel());
  }

  void _suspend() {
    _suspended = true;
    _cancel();
  }

  void _resume() {
    _suspended = false;
    _sync();
  }

  @override
  void dispose() {
    _disposed = true;
    downloads.removeListener(_sync);
    _lifecycle?.dispose();
    _cancel();
    super.dispose();
  }
}
