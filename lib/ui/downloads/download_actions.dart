import 'package:flutter/material.dart';

import '../../download_collections.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../widgets/focus_ring.dart';

String formatBytes(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
    : bytes >= 1 << 20
    ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).round()} KB';

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<bool> downloadEpisodes(
  BuildContext context,
  LocalStore store,
  DramaDetail detail,
  List<Episode> episodes,
) async {
  if (episodes.isEmpty) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final added = await enqueueEpisodes(
      AppScope.of(context).repository,
      store,
      detail,
      episodes,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(added == 0 ? '所选剧集已在下载列表中' : '已加入下载 $added 集')),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    return false;
  }
}

Future<bool> confirmRemoval(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final colors = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        FocusRing(
          radius: 20,
          child: TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
        ),
        FocusRing(
          radius: 20,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<bool> removeDownloads(
  BuildContext context,
  List<String> ids, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await controlDownloadJobs(
    AppScope.of(context).repository,
    'remove',
    ids,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.failures.isEmpty
            ? done
            : '${result.failures.length} 集未能删除：${result.failures.values.first}',
      ),
    ),
  );
  return result.failures.isEmpty;
}

class SourceTag extends StatelessWidget {
  const SourceTag(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        SourceSite.byId(source).name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
