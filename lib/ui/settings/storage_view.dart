import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_device.dart';
import '../../core_bridge.dart';
import '../../local_store.dart';
import '../app_scope.dart';
import '../widgets/focus_ring.dart';
import '../widgets/group_card.dart';
import '../widgets/status_view.dart';
import 'settings_rows.dart';

String storageSize(int bytes) {
  if (bytes < 0) return '暂不可用';
  if (bytes < 1 << 20) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1 << 30) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
}

class StorageView extends StatefulWidget {
  const StorageView({super.key, required this.store});
  final LocalStore store;

  @override
  State<StorageView> createState() => _StorageViewState();
}

class _StorageViewState extends State<StorageView> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final info = await AppScope.of(context).repository.storage();
      if (mounted) {
        setState(() {
          _info = info;
          _error = null;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    }
  }

  Future<String?> _pickParent() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return FilePicker.getDirectoryPath(dialogTitle: '选择下载保存位置');
    }
    final support = await getApplicationSupportDirectory();
    final directories = <String, String>{support.path: '应用内部存储'};
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectories() ?? [];
      for (final (index, directory) in external.indexed) {
        directories[directory.path] = index == 0
            ? '设备共享存储（应用目录）'
            : 'SD 卡 ${index + 1}（应用目录）';
      }
    } else {
      final documents = await getApplicationDocumentsDirectory();
      directories[documents.path] = '文件 App 可见目录';
    }
    if (!mounted) return null;
    return showOptionDialog(
      context,
      title: '选择下载位置',
      options: directories,
      selected: null,
    );
  }

  Future<void> _move() async {
    final parent = await _pickParent();
    if (parent == null || !mounted) return;
    await _migrate(parent, parent);
  }

  Future<void> _restore() => _migrate('', '应用默认目录');

  Future<void> _setAutoExport(bool value) => saveSetting(context, () async {
    if (value && !await AppDevice.requestVideoExport()) {
      throw AppFailure('未获得存储权限，无法自动导出');
    }
    await widget.store.setAutoExport(value);
  });

  Future<void> _migrate(String parent, String destination) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移已下载内容？'),
        content: Text(
          '将下载目录里的全部内容迁移到：\n$destination\n\n下载会先暂停，复制成功后清理旧目录。请保证目标有足够空间，并在完成后继续下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = AppScope.of(context).repository;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            spacing: 20,
            children: [
              CircularProgressIndicator(),
              Expanded(child: Text('正在迁移，请保持应用运行…')),
            ],
          ),
        ),
      ),
    );
    try {
      await repository.moveDownloads(parent);
    } catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    } finally {
      navigator.pop();
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) {
      return _error == null
          ? const StatusView.loading()
          : StatusView(
              title: '无法读取下载目录',
              message: _error,
              icon: Icons.folder_off_outlined,
              action: '重试',
              onAction: _refresh,
            );
    }
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final directory = info['directory'] as String? ?? '';
    final admin = widget.store.profile.admin;
    final isDefault = info['default'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        GroupCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    '已使用 ${storageSize((info['bytes'] as num?)?.toInt() ?? 0)}',
                    style: text.headlineSmall,
                  ),
                  Text(
                    '剩余 ${storageSize((info['free'] as num?)?.toInt() ?? -1)} · ${info['files'] ?? 0} 个文件',
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            SettingsTile(
              title: '当前下载目录',
              subtitle: directory,
              trailing: FocusRing(
                radius: 999,
                child: IconButton(
                  tooltip: '复制路径',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: directory)),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            SettingsTile(
              title: '更改并迁移目录',
              subtitle: admin ? '下载会先暂停，复制成功后清理旧目录' : '需要管理员',
              enabled: admin,
              onTap: _move,
            ),
            const Divider(indent: 16, endIndent: 16),
            SettingsTile(
              title: '恢复默认下载目录',
              subtitle: !admin
                  ? '需要管理员'
                  : isDefault
                  ? '正在使用默认目录'
                  : '迁移回应用默认目录',
              enabled: admin && !isDefault,
              onTap: _restore,
            ),
            const Divider(indent: 16, endIndent: 16),
            SettingsTile(title: '刷新用量', onTap: _refresh),
          ],
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => GroupCard(
              children: [
                SwitchTile(
                  title: '下载完成后自动导出',
                  subtitle: '导出到 Movies/剧名/，相册和文件管理器可见，卸载后保留',
                  value: widget.store.autoExport,
                  onChanged: _setAutoExport,
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchTile(
                  title: '自动导出后删除 App 内副本',
                  subtitle: '删除后 App 内不能再离线播放',
                  value: widget.store.deleteAfterAutoExport,
                  onChanged: (value) => saveSetting(
                    context,
                    () => widget.store.setDeleteAfterAutoExport(value),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchTile(
                  title: '手动导出后删除 App 内副本',
                  subtitle: '在已下载剧页「编辑」里点「导出」后删除',
                  value: widget.store.deleteAfterManualExport,
                  onChanged: (value) => saveSetting(
                    context,
                    () => widget.store.setDeleteAfterManualExport(value),
                  ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            _error ?? '在下载页删除不需要的分集，在本地媒体页删除合并成品，可释放空间。',
            style: text.bodyMedium?.copyWith(
              color: _error == null ? colors.onSurfaceVariant : colors.error,
            ),
          ),
        ),
      ],
    );
  }
}
