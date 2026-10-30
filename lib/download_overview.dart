import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';

class DownloadOverview extends ChangeNotifier {
  DownloadOverview(this.repository, this.store, {this.interval = _interval}) {
    store.addListener(_sync);
    _sync();
  }

  static const _interval = Duration(seconds: 2);
  final AppRepository repository;
  final LocalStore store;
  final Duration interval;
  Timer? _timer;
  int? _epoch;
  int _request = 0;
  bool _loading = false;
  bool _disposed = false;
  List<DownloadJob> _jobs = const [];

  bool get available => store.canDownload && repository.supportsDownloads;
  List<DownloadJob> get jobs => _jobs;
  int get active => _jobs.where((job) => job.active || job.converting).length;
  int get completed => _jobs.where((job) => job.completed).length;
  int get completedBytes => _jobs
      .where((job) => job.completed)
      .fold(0, (total, job) => total + job.bytes);
  DownloadJob? get current =>
      _jobs.where((job) => job.state == 'downloading').firstOrNull ??
      _jobs.where((job) => job.active).firstOrNull;

  void _sync() {
    if (!available) {
      _stop();
      return;
    }
    if (_epoch != store.profileEpoch) {
      _epoch = store.profileEpoch;
      _request++;
      _loading = false;
      _replace(const []);
    }
    if (_timer == null) {
      _timer = Timer.periodic(interval, (_) => refresh());
      refresh();
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _epoch = null;
    _request++;
    _loading = false;
    _replace(const []);
  }

  static String _signature(List<DownloadJob> jobs) => [
    for (final job in jobs)
      '${job.id}|${job.state}|${job.progress}|${job.bytes}|${job.total}|'
          '${job.actualQuality}|${job.error}|${job.drama.title}',
  ].join('\n');

  void _replace(List<DownloadJob> jobs) {
    if (_signature(jobs) == _signature(_jobs)) return;
    _jobs = jobs;
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (_loading || !available) return;
    _loading = true;
    final request = _request;
    try {
      final jobs = await repository.downloads();
      if (!_disposed && request == _request) _replace(jobs);
    } catch (_) {
    } finally {
      if (request == _request) _loading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    store.removeListener(_sync);
    super.dispose();
  }
}
