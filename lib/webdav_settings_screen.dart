import 'package:flutter/material.dart';

import 'backup_actions.dart';
import 'local_store.dart';
import 'webdav_sync.dart';

String _formatTime(DateTime? time) {
  if (time == null) return '从未';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class WebDavSettingsScreen extends StatefulWidget {
  const WebDavSettingsScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<WebDavSettingsScreen> createState() => _WebDavSettingsScreenState();
}

class _WebDavSettingsScreenState extends State<WebDavSettingsScreen> {
  final _uriController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _directoryController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  DateTime? _lastBackupAt;
  DateTime? _remoteBackupAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _uriController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _directoryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final preferences = widget.store.preferences;
    final config = await WebDavConfig.load(preferences);
    final last = await WebDavSync.lastBackupAt(preferences);
    if (!mounted) return;
    setState(() {
      _uriController.text = config.uri;
      _usernameController.text = config.username;
      _passwordController.text = config.password;
      _directoryController.text = config.directory;
      _lastBackupAt = last;
    });
    if (config.isConfigured) await _refreshRemoteBackupAt();
  }

  Future<void> _refreshRemoteBackupAt() async {
    try {
      final remote = await WebDavClient(
        await WebDavConfig.load(widget.store.preferences),
      ).backupModifiedAt();
      if (!mounted) return;
      setState(() => _remoteBackupAt = remote);
    } on WebDavException catch (error) {
      _showMessage(error.message);
    }
  }

  WebDavConfig _configFromFields() => WebDavConfig(
    uri: _uriController.text,
    username: _usernameController.text,
    password: _passwordController.text,
    directory: _directoryController.text,
  );

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final config = _configFromFields();
      if (!config.isConfigured) {
        throw const WebDavException('请先填写 WebDAV 地址');
      }
      await config.save(widget.store.preferences);
      final error = await WebDavSync.testConnection(config);
      _showMessage(
        error == null ? '配置已保存，连接正常' : '配置已保存，但连接失败：$error',
      );
      if (error == null) await _refreshRemoteBackupAt();
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: SingleChildScrollView(child: Text(text))),
    );
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      await WebDavSync.backup(
        preferences: widget.store.preferences,
        store: widget.store,
      );
      if (!mounted) return;
      setState(() => _lastBackupAt = DateTime.now());
      _showMessage('备份已上传到 WebDAV');
      await _refreshRemoteBackupAt();
    } catch (error) {
      _showMessage('备份失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final content = await WebDavSync.fetchBackup(
        widget.store.preferences,
      );
      if (!mounted) return;
      await restoreBackupContent(context, widget.store, content);
    } catch (error) {
      _showMessage('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 备份')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '通过 WebDAV 备份与恢复配置、观看记录和追剧，内容与「导出配置备份」一致，不含视频文件。凭据只保存在本机。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _uriController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '地址',
                  hintText: 'https://dav.example.com/dav',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '账号',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: _obscurePassword
                        ? const Icon(Icons.visibility_outlined)
                        : const Icon(Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _directoryController,
                decoration: const InputDecoration(
                  labelText: '目录',
                  hintText: WebDavConfig.defaultDirectory,
                  helperText: '备份文件存放目录，留空使用默认目录',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存并测试连接'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _backup,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('备份到 WebDAV'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('从 WebDAV 恢复'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                color: colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusLine(label: '本地上次备份', value: _formatTime(_lastBackupAt)),
                      _StatusLine(label: '远端备份时间', value: _formatTime(_remoteBackupAt)),
                      if (_remoteBackupAt != null &&
                          _lastBackupAt != null &&
                          _remoteBackupAt!.isBefore(_lastBackupAt!))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '本机备份比远端新，建议重新上传',
                            style: TextStyle(
                              color: colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    ),
  );
}
