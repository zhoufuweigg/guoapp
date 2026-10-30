import 'dart:math';

import 'package:path/path.dart' as path;

import 'app_device.dart';
import 'core_bridge.dart';
import 'download_collections.dart';
import 'download_merge.dart';
import 'models.dart';

String exportFileName(int number, int episodes) {
  final width = max(2, '${max(number, episodes)}'.length);
  return '第${'$number'.padLeft(width, '0')}集.mp4';
}

Future<void> exportDownload(
  AppRepository repository,
  DownloadJob job, {
  required bool delete,
}) async {
  final plan = await repository.localPlayback(job.drama, job.episode);
  if (plan == null ||
      !plan.local ||
      plan.decryptionKey.isNotEmpty ||
      path.extension(plan.url).toLowerCase() != '.mp4') {
    throw AppFailure('第 ${job.episode.number} 集还没有处理成 mp4，暂时不能导出');
  }
  await AppDevice.exportVideo(
    plan.url,
    safeFileName(job.drama.title),
    exportFileName(job.episode.number, job.drama.episodes),
  );
  if (!delete) return;
  final result = await controlDownloadJobs(repository, 'remove', [job.id]);
  if (result.failures.isNotEmpty) {
    throw AppFailure('已导出，但 App 内副本未能删除：${result.failures.values.first}');
  }
}
