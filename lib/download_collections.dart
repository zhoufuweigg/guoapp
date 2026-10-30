import 'dart:math';

import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';

class DownloadBatchResult {
  const DownloadBatchResult({
    this.completed = const [],
    this.failures = const {},
  });
  final List<String> completed;
  final Map<String, String> failures;
  factory DownloadBatchResult.fromJson(Map<String, dynamic> data) =>
      DownloadBatchResult(
        completed: (data['completed'] as List? ?? [])
            .whereType<String>()
            .toList(),
        failures: (data['failures'] as Map? ?? {}).map(
          (key, value) => MapEntry('$key', '$value'),
        ),
      );
}

const downloadBatchSize = 500;

class DownloadFill {
  const DownloadFill(
    this.detail,
    this.episodes, {
    required this.missing,
    required this.skippedVip,
  });
  final DramaDetail detail;
  final List<Episode> episodes;
  final int missing;
  final int skippedVip;
}

class DownloadedDrama {
  DownloadedDrama(this.drama, this.episodes, this.pending);
  final Drama drama;
  final List<DownloadJob> episodes;
  final int pending;
  int get bytes => episodes.fold(0, (total, job) => total + job.bytes);
}

bool _listed(DownloadJob job) => job.state != 'removing';

List<DownloadJob> pendingDownloads(Iterable<DownloadJob> jobs) =>
    [
      for (final job in jobs)
        if (!job.completed && _listed(job)) job,
    ]..sort((a, b) {
      final order = a.created.compareTo(b.created);
      return order != 0 ? order : a.episode.number.compareTo(b.episode.number);
    });

List<DownloadedDrama> downloadedDramas(Iterable<DownloadJob> jobs) {
  final completed = <String, List<DownloadJob>>{};
  final pending = <String, int>{};
  for (final job in jobs) {
    final id = job.drama.id;
    if (job.completed) {
      (completed[id] ??= []).add(job);
    } else if (_listed(job)) {
      pending[id] = (pending[id] ?? 0) + 1;
    }
  }
  int latest(List<DownloadJob> rows) =>
      rows.map((job) => job.created).reduce(max);
  final groups = completed.entries.toList()
    ..sort((a, b) => latest(b.value).compareTo(latest(a.value)));
  return [
    for (final MapEntry(key: id, value: rows) in groups)
      DownloadedDrama(
        rows.reduce((a, b) => b.created > a.created ? b : a).drama,
        rows..sort((a, b) => a.episode.number.compareTo(b.episode.number)),
        pending[id] ?? 0,
      ),
  ];
}

List<SourceSite> downloadSources(Iterable<DownloadJob> jobs) => [
  for (final site in SourceSite.values)
    if (jobs.any((job) => job.drama.source == site.id)) site,
];

({Set<int> downloaded, Set<int> downloading}) downloadMarks(
  Iterable<DownloadJob> jobs,
  String drama,
) => (
  downloaded: {
    for (final job in jobs)
      if (job.drama.id == drama && job.completed) job.episode.number,
  },
  downloading: {
    for (final job in jobs)
      if (job.drama.id == drama && !job.completed && _listed(job))
        job.episode.number,
  },
);

Future<int> enqueueEpisodes(
  AppRepository repository,
  LocalStore store,
  DramaDetail detail,
  List<Episode> episodes,
) async {
  final quality = store.downloadPreferences.quality;
  var added = 0;
  for (var offset = 0; offset < episodes.length; offset += downloadBatchSize) {
    added += await repository.enqueueDownloads(
      detail,
      episodes.sublist(
        offset,
        min(offset + downloadBatchSize, episodes.length),
      ),
      quality: quality,
    );
  }
  return added;
}

Future<DownloadBatchResult> controlDownloadJobs(
  AppRepository repository,
  String command,
  List<String> ids,
) async {
  final completed = <String>[];
  final failures = <String, String>{};
  for (var offset = 0; offset < ids.length; offset += downloadBatchSize) {
    final chunk = ids.sublist(
      offset,
      min(offset + downloadBatchSize, ids.length),
    );
    try {
      final result = await repository.controlDownloadBatch(command, chunk);
      completed.addAll(result.completed);
      failures.addAll(result.failures);
    } catch (error) {
      failures.addAll({for (final id in chunk) id: error.toString()});
    }
  }
  return DownloadBatchResult(completed: completed, failures: failures);
}

class DownloadCollectionUpdater extends ChangeNotifier {
  DownloadCollectionUpdater(this.repository, this.store)
    : _epoch = store.profileEpoch;
  final AppRepository repository;
  final LocalStore store;
  final int _epoch;
  bool _disposed = false;
  bool _stop = false;
  bool busy = false;
  String status = '';
  String? error;
  int added = 0;

  bool get valid =>
      !_disposed && store.canDownload && store.profileEpoch == _epoch;
  void _check(String source) {
    if (!valid || _stop || !store.allowsSource(source)) {
      throw AppFailure('更新已停止；已加入的任务保留');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    _stop = true;
  }

  Future<DownloadFill> inspect(Drama drama, Iterable<DownloadJob> jobs) async {
    void allowed() {
      if (!valid || !store.allowsSource(drama.source)) {
        throw AppFailure('当前用户无法下载此剧');
      }
    }

    allowed();
    final fresh = await repository.detail(drama);
    allowed();
    if (fresh.drama.id != drama.id || fresh.drama.source != drama.source) {
      throw AppFailure('剧集信息不匹配，请重试');
    }
    final detail = DramaDetail(drama.merge(fresh.drama), fresh.episodes);
    if (detail.episodes.isEmpty) throw AppFailure('暂未取得分集，请更新资料后重试');
    repository.catalogUpdates.publish(detail.drama);
    await store.refreshDrama(detail.drama);
    allowed();
    final includeVip = store.downloadPreferences.includeVip;
    final known = {
      for (final job in jobs)
        if (job.drama.id == drama.id && _listed(job) && job.state != 'failed')
          job.episode.number,
    };
    final all = {
      for (final episode in detail.episodes) episode.number: episode,
    }.values;
    final missing = [
      for (final episode in all)
        if (!known.contains(episode.number)) episode,
    ];
    return DownloadFill(
      detail,
      [
        for (final episode in all)
          if (includeVip || !episode.vip) episode,
      ],
      missing: missing.where((episode) => includeVip || !episode.vip).length,
      skippedVip: includeVip
          ? 0
          : missing.where((episode) => episode.vip).length,
    );
  }

  Future<void> fill(DownloadFill plan) async {
    final drama = plan.detail.drama;
    final detail = plan.detail;
    final episodes = plan.episodes;
    if (busy || !valid) return;
    busy = true;
    _stop = false;
    error = null;
    added = 0;
    _notify();
    try {
      final preferences = store.downloadPreferences;
      for (var offset = 0; offset < episodes.length; offset += 500) {
        _check(drama.source);
        status =
            '正在补齐 ${drama.title} · ${min(offset + 500, episodes.length)}/${episodes.length} 集';
        _notify();
        added += await repository.updateDownloadCollection(
          detail,
          episodes.sublist(offset, min(offset + 500, episodes.length)),
          quality: preferences.quality,
        );
      }
      _check(drama.source);
      status = added == 0 ? '没有需要补齐的集' : '已加入下载 $added 集';
    } catch (value) {
      error = value.toString();
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop = true;
    super.dispose();
  }
}
