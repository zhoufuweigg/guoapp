import 'package:flutter/material.dart';

import 'local_store.dart';

/// 从备份内容恢复：走本地既有校验、确认与导入实现。
/// 文件选择恢复与 WebDAV 恢复共用，避免两套恢复逻辑。
Future<void> restoreBackupContent(
  BuildContext context,
  LocalStore store,
  String content,
) async {
  final data = store.validateBackup(content);
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('恢复备份？'),
      content: Text(
        '包含 ${(data['profiles'] as List).length} 个用户。将替换本机的用户、追剧、观看记录和偏好设置；已下载视频保留。恢复后使用备份内的管理员密码登录。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('恢复'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return;
  await store.importBackup(content);
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}
