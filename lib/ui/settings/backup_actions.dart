import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_build.dart';
import '../../local_store.dart';
import '../users/password_dialog.dart';
import '../widgets/focus_ring.dart';

Future<String?> exportBackupFile(LocalStore store) async {
  final content = await store.exportBackup();
  final saved = await FilePicker.saveFile(
    fileName:
        '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
    bytes: Uint8List.fromList(utf8.encode(content)),
    mimeType: 'application/json',
  );
  return saved == null ? null : '备份已保存';
}

Future<String?> _pickBackup() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (file == null) return null;
  final size = await file.length();
  if (size == null || size > 8 * 1024 * 1024) {
    throw const FormatException('备份文件过大或无法读取');
  }
  return utf8.decode(await file.readAsBytes());
}

Future<String?> restoreBackupFile(
  BuildContext context,
  LocalStore store,
) async {
  final content = await _pickBackup();
  if (content == null || !context.mounted) return null;
  final data = store.validateBackup(content);
  if (!context.mounted) return null;
  final accepted = await _confirm(
    context,
    title: '恢复备份？',
    message:
        '包含 ${(data['profiles'] as List).length} 个用户。将替换本机的用户、追剧、观看记录和偏好设置；已下载视频保留。恢复后使用备份内的管理员密码登录。',
    action: '恢复',
  );
  if (accepted != true || !context.mounted) return null;
  final navigator = Navigator.of(context);
  await store.importBackup(content);
  navigator.popUntil((route) => route.isFirst);
  return null;
}

Future<String?> recoverBackupFile(
  BuildContext context,
  LocalStore store,
) async {
  final content = await _pickBackup();
  if (content == null || !context.mounted) return null;
  store.validateBackup(content);
  final accepted = await _confirm(
    context,
    title: '从备份恢复用户与记录？',
    message: '将使用这份备份替换损坏的用户配置、追剧、观看记录和偏好设置；已下载视频保留。建议先导出原始配置。',
    action: '继续恢复',
  );
  if (accepted != true || !context.mounted) return null;
  await showPasswordDialog(
    context,
    title: '验证管理员',
    helper: '原配置或备份中的管理员密码',
    onSubmit: (pin) => store.recoverBackup(content, pin: pin),
  );
  return null;
}

Future<String?> exportRecoveryFile(LocalStore store) async {
  final saved = await FilePicker.saveFile(
    fileName: '$appSlug-recovery.json',
    bytes: Uint8List.fromList(utf8.encode(store.exportRecoveryData())),
    mimeType: 'application/json',
  );
  return saved == null ? null : '原始配置已保存';
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) => showDialog<bool>(
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
          child: const Text('取消'),
        ),
      ),
      FocusRing(
        radius: 20,
        child: FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ),
    ],
  ),
);
