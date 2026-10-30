import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as path;

import 'core_bridge.dart';
import 'media_pipeline.dart';

class CoverDecoder {
  CoverDecoder({MediaExecutor Function()? createExecutor})
    : _createExecutor = createExecutor ?? FFmpegExecutor.new;
  static const _workers = 3;
  final MediaExecutor Function() _createExecutor;
  final _pending = <String, Future<String>>{};
  final _queue = <Future<void> Function()>[];
  var _running = 0;
  var _pruning = false;
  DateTime? _prunedAt;

  Future<String> convert(
    String original,
    Future<Map<String, dynamic>> Function() prepare, {
    bool force = false,
  }) async {
    final stat = await File(original).stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw AppFailure('海报缓存已失效，请重试');
    }
    final directory = Directory(
      path.join(path.dirname(original), 'compatible-v1'),
    );
    final key =
        '${path.basenameWithoutExtension(original)}-${stat.modified.microsecondsSinceEpoch}-${stat.size}';
    final target = File(path.join(directory.path, '$key.jpg'));
    if (!force && await _isJPEG(target)) {
      await target.setLastModified(DateTime.now());
      return target.path;
    }
    if (_pending.containsKey(key)) return _pending[key]!;
    if (_pending.length >= 96) throw AppFailure('海报正在处理，请稍后重试');
    final result = _schedule(() => _convert(original, target, prepare));
    _pending[key] = result;
    try {
      return await result;
    } finally {
      if (identical(_pending[key], result)) _pending.remove(key);
    }
  }

  Future<String> _schedule(Future<String> Function() job) {
    final completer = Completer<String>();
    _queue.add(
      () => job()
          .then(completer.complete, onError: completer.completeError)
          .whenComplete(() {
            _running--;
            _drain();
          }),
    );
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_running < _workers && _queue.isNotEmpty) {
      _running++;
      unawaited(_queue.removeLast()());
    }
  }

  void _schedulePrune(String directory, String keep) {
    final now = DateTime.now();
    if (_pruning ||
        _prunedAt != null &&
            now.difference(_prunedAt!) < const Duration(seconds: 30)) {
      return;
    }
    _pruning = true;
    _prunedAt = now;
    unawaited(
      _pruneInBackground(
        directory,
        keep,
      ).then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _pruning = false;
      }),
    );
  }

  Future<bool> _isJPEG(File file) async {
    try {
      final length = await file.length();
      if (length < 4 || length > 4 * 1024 * 1024) return false;
      final handle = await file.open();
      try {
        final header = await handle.read(3);
        return header.length == 3 &&
            header[0] == 255 &&
            header[1] == 216 &&
            header[2] == 255;
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      return false;
    }
  }

  Future<String> _convert(
    String original,
    File target,
    Future<Map<String, dynamic>> Function() prepare,
  ) async {
    final prepared = await prepare();
    if (prepared['heic'] != true) {
      return prepared['path'] as String? ?? original;
    }
    final input = prepared['input'] as String? ?? '';
    if (input.isEmpty) throw AppFailure('海报格式转换失败，请重试');
    final intermediate = File('${target.path}.part');
    final executor = _createExecutor();
    Future<void>? work;
    try {
      await target.parent.create(recursive: true);
      final orientation = prepared['filters'] as String? ?? '';
      final filters = [
        if (orientation.isNotEmpty) orientation,
        "scale=w='min(800,iw)':h='min(800,ih)':force_original_aspect_ratio=decrease",
      ].join(',');
      work = executor.run([
        '-max_alloc',
        '67108864',
        '-threads',
        '1',
        '-f',
        'hevc',
        '-i',
        input,
        '-frames:v',
        '1',
        '-an',
        '-sn',
        '-vf',
        filters,
        '-filter_threads',
        '1',
        '-threads',
        '1',
        '-c:v',
        'mjpeg',
        '-pix_fmt',
        'yuvj420p',
        '-q:v',
        '3',
        '-f',
        'image2',
        intermediate.path,
      ]);
      await work.timeout(const Duration(seconds: 12));
      if (!await _isJPEG(intermediate)) throw AppFailure('海报转换未生成有效图片');
      if (await target.exists()) await target.delete();
      await intermediate.rename(target.path);
      _schedulePrune(target.parent.path, target.path);
      return target.path;
    } on TimeoutException {
      await executor.cancel();
      try {
        await work?.timeout(const Duration(seconds: 5));
      } catch (_) {}
      throw AppFailure('海报转换超时，请重试');
    } finally {
      for (final file in [if (input != original) File(input), intermediate]) {
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          continue;
        }
      }
    }
  }

  static Future<void> _pruneInBackground(String directory, String keep) =>
      Isolate.run(() => _prune(Directory(directory), keep));

  static void _prune(Directory directory, String keep) {
    final entries = <(File, FileStat)>[];
    var size = 0;
    for (final entry in directory.listSync(followLinks: false)) {
      if (entry is! File) continue;
      final stat = entry.statSync();
      if (entry.path.endsWith('.part')) {
        if (DateTime.now().difference(stat.modified) >
            const Duration(minutes: 1)) {
          entry.deleteSync();
        }
      } else if (entry.path.endsWith('.jpg')) {
        entries.add((entry, stat));
        size += stat.size;
      }
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var count = entries.length;
    for (final entry in entries) {
      if (count <= 1000 && size <= 96 * 1024 * 1024) break;
      if (entry.$1.path == keep) continue;
      entry.$1.deleteSync();
      count--;
      size -= entry.$2.size;
    }
  }
}
