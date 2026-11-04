import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core_bridge.dart';
import 'app_theme.dart';
import 'background_downloads.dart';
import 'backup_actions.dart';
import 'local_store.dart';
import 'other_settings_screen.dart';
import 'playback_preferences.dart';
import 'profiles_screen.dart';
import 'app_build.dart';
import 'sources_screen.dart';
import 'webdav_settings_screen.dart';
import 'widgets.dart';
import 'resource_settings_screen.dart';
import 'theme_settings_screen.dart';
import 'lan_screen.dart';
import 'diary_service.dart';

String storageSize(int bytes) {
  if (bytes < 0) return '暂不可用';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = false,
  });
  final AppRepository repository;
  final LocalStore store;

  /// 内嵌为一级 tab 页面（由首页底栏直接切入，不再作为二级路由 push）：
  /// 不再自绘 AppBar 与返回按钮，顶栏由宿主页面提供。
  final bool embedded;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _backup(bool restore) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!restore) {
        final content = await widget.store.exportBackup();
        final saved = await FilePicker.saveFile(
          fileName:
              '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
          bytes: Uint8List.fromList(utf8.encode(content)),
          mimeType: 'application/json',
        );
        if (saved != null && mounted) setState(() => _message = '备份已保存');
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (file == null || !mounted) return;
        final size = await file.length();
        if (size == null || size > 8 * 1024 * 1024) {
          throw const FormatException('备份文件过大或无法读取');
        }
        final content = utf8.decode(await file.readAsBytes());
        if (!mounted) return;
        await restoreBackupContent(context, widget.store, content);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget? _backgroundCache;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        // 性能：页面不在前台时复用缓存子树，跳过 store 通知触发的整页重建。
        builder: (context, _) {
          final route = ModalRoute.of(context);
          if (route != null && !route.isCurrent && _backgroundCache != null) {
            return _backgroundCache!;
          }
          final child = Scaffold(
            appBar: widget.embedded
                ? null
                : AppBar(title: const Text('设置与备份')),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  // 内嵌为一级 tab 时底部补偿悬浮底栏高度（extendBody 时
                  // MediaQuery.padding.bottom = 底栏高度），避免列表尾部被遮挡。
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 +
                        (widget.embedded
                            ? MediaQuery.paddingOf(context).bottom
                            : 0),
                  ),
                  children: [
                    ListTile(
                      key: const ValueKey('lan-settings'),
                      leading: const Icon(Icons.devices_rounded),
                      title: const Text('设备互联'),
                      subtitle: const Text('局域网自动同步追剧与推送播放'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openLanSync(context),
                    ),
                    if (widget.repository.supportsSourceManagement)
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('站源管理'),
                        subtitle: const Text('独立更新、连接与播放检测'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => SourcesScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        ),
                      ),
                    ListTile(
                      key: const ValueKey('theme-setting'),
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('主题设置'),
                      subtitle: Text(
                        '${AppTheme.label(widget.store.themeMode)} · '
                        '模糊、悬浮底栏、深浅色与界面缩放',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ThemeSettingsScreen(store: widget.store),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('用户管理'),
                      subtitle: Text('当前：${widget.store.profile.name}'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ProfilesScreen(store: widget.store),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const ValueKey('diary-setting'),
                      leading: const Icon(Icons.receipt_long_rounded),
                      title: const Text('播放调试日记'),
                      subtitle: const Text('查看并复制应用运行与播放器的详细事件日志'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => DiaryService.showDiaryDialog(context),
                    ),

                    ListTile(
                      key: const ValueKey('playback-gesture-setting'),
                      leading: const Icon(Icons.gesture_rounded),
                      title: const Text('播放器与手势'),
                      subtitle: const Text('画面比例、滑动调节、双击与长按倍速等播放设置'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PlaybackGestureScreen(store: widget.store),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const ValueKey('other-settings'),
                      leading: const Icon(Icons.more_horiz_rounded),
                      title: const Text('其他设置'),
                      subtitle: const Text('浏览进度等杂项功能'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => OtherSettingsScreen(store: widget.store),
                        ),
                      ),
                    ),
                    if (widget.store.canDownload)
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: const Text('下载偏好'),
                        subtitle:
                            Text(widget.store.downloadPreferences.qualityLabel),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                DownloadPreferencesScreen(store: widget.store),
                          ),
                        ),
                      ),
                    if (widget.store.canDownload)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('下载目录与空间'),
                        subtitle: const Text('查看存储用量、迁移已下载文件'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => StorageScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        ),
                      ),
                    if (widget.store.profile.admin) ...[
                      ListTile(
                        leading: const Icon(Icons.settings_ethernet_rounded),
                        title: const Text('网络与资源'),
                        subtitle: const Text('代理、目录请求间隔、下载并发与站源目录'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ResourceSettingsScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        ),
                      ),
                      SwitchListTile(
                        value: widget.store.autoExport,
                        title: const Text('下载完成后自动导出 Emby'),
                        subtitle: const Text(
                          '在下载目录的 exports 中生成视频和海报 URL 元数据，可将该目录加入 Emby 媒体库。',
                        ),
                        onChanged: _busy
                            ? null
                            : (value) async {
                                try {
                                  if (value) {
                                    await BackgroundDownloads.ensureStarted();
                                  }
                                  await widget.store.setAutoExport(value);
                                } catch (error) {
                                  if (mounted) {
                                    setState(() => _message = error.toString());
                                  }
                                }
                              },
                      ),
                      SwitchListTile(
                        value: widget.store.exportPosters,
                        title: const Text('同时导出海报文件'),
                        subtitle: const Text('默认只写海报 URL。源站海报需要解密或外部读取失败时可开启。'),
                        onChanged: _busy
                            ? null
                            : (value) => saveUserChange(
                                  context,
                                  () => widget.store.setExportPosters(value),
                                ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: const Text('导出配置备份'),
                        subtitle: const Text('包含本地用户、追剧、历史和设置，不含视频文件'),
                        onTap: _busy ? null : () => _backup(false),
                      ),
                      ListTile(
                        leading: const Icon(Icons.restore),
                        title: const Text('恢复配置备份'),
                        onTap: _busy ? null : () => _backup(true),
                      ),

                      ListTile(
                        key: const ValueKey('webdav-settings'),
                        leading: const Icon(Icons.cloud_sync_outlined),
                        title: const Text('WebDAV 备份'),
                        subtitle: const Text('通过 WebDAV 同步配置、观看记录与追剧'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      WebDavSettingsScreen(store: widget.store),
                                ),
                              ),
                      ),
                    ],
                    if (Platform.isIOS)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('iOS 下载和媒体处理需要保持应用在前台；切到后台会暂停，回到前台后可继续。'),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(_message!),
                      ),
                  ],
                ),
              ),
            ),
          );
          _backgroundCache = child;
          return child;
        },
      );
}

class PlaybackGestureScreen extends StatefulWidget {
  const PlaybackGestureScreen({super.key, required this.store});
  final LocalStore store;
  @override
  State<PlaybackGestureScreen> createState() => _PlaybackGestureScreenState();
}

class _PlaybackGestureScreenState extends State<PlaybackGestureScreen> {
  bool _busy = false;

  Future<void> _update(PlaybackPreferences next) async {
    setState(() => _busy = true);
    try {
      await widget.store.setPlaybackPreferences(next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('播放器与手势')),
    body: AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final preferences = widget.store.playbackPreferences;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('画面比例'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in fitTypeEntries)
                      ChoiceChip(
                        key: ValueKey('gesture-fit-${entry.key}'),
                        label: Text(entry.label),
                        selected: entry.key == preferences.fitType,
                        onSelected: _busy
                            ? null
                            : (_) => _update(
                                preferences.copyWith(fitType: entry.key),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '自动：完整显示画面；裁剪：填满屏幕并裁掉多余部分；拉伸：强制铺满；等宽 / 等高：按单边对齐。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                const Text('默认倍速'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final speed in playbackSpeeds)
                      ChoiceChip(
                        key: ValueKey('gesture-speed-$speed'),
                        label: Text('${speed}x'),
                        selected: speed == preferences.speed,
                        onSelected: _busy
                            ? null
                            : (_) => _update(
                                preferences.copyWith(speed: speed),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile.adaptive(
                  key: const ValueKey('gesture-slide-volume-brightness'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('滑动调节音量与亮度'),
                  subtitle: const Text('左侧上下滑调亮度，右侧上下滑调音量'),
                  value: preferences.slideVolumeBrightness,
                  onChanged: _busy
                      ? null
                      : (value) => _update(
                          preferences.copyWith(slideVolumeBrightness: value),
                        ),
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('gesture-slide-fullscreen'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('中部滑动切换全屏'),
                  subtitle: const Text('播放器中三分之一区域上滑进入全屏、下滑退出全屏'),
                  value: preferences.slideFullscreen,
                  onChanged: _busy
                      ? null
                      : (value) => _update(
                          preferences.copyWith(slideFullscreen: value),
                        ),
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('gesture-quick-double-tap'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('双击快进快退'),
                  subtitle: const Text(
                    '开启后双击左 / 右区域快退 / 快进；关闭后双击任意位置播放暂停',
                  ),
                  value: preferences.quickDoubleTap,
                  onChanged: _busy
                      ? null
                      : (value) => _update(
                          preferences.copyWith(quickDoubleTap: value),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('快进快退步长'),
                      for (final seconds in const [5, 10, 15, 30])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('gesture-double-tap-$seconds'),
                            label: Text('$seconds 秒'),
                            selected:
                                seconds == preferences.doubleTapSeekSeconds,
                            onSelected: _busy
                                ? null
                                : (_) => _update(
                                    preferences.copyWith(
                                      doubleTapSeekSeconds: seconds,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('横滑进度幅度'),
                      for (final seconds in dragSeekSteps)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('gesture-drag-seek-$seconds'),
                            label: Text('$seconds 秒'),
                            selected: seconds == preferences.dragSeekSeconds,
                            onSelected: _busy
                                ? null
                                : (_) => _update(
                                    preferences.copyWith(
                                      dragSeekSeconds: seconds,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('长按倍速'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final speed in const [2.0, 2.5, 3.0, 4.0])
                      ChoiceChip(
                        key: ValueKey('gesture-long-press-speed-$speed'),
                        label: Text('${speed}x'),
                        selected: speed == preferences.longPressSpeed,
                        onSelected: _busy
                            ? null
                            : (_) => _update(
                                preferences.copyWith(longPressSpeed: speed),
                              ),
                      ),
                  ],
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('gesture-auto-long-press-speed'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('长按使用动态倍速'),
                  subtitle: const Text('开启后长按倍速为当前播放速度的 2 倍'),
                  value: preferences.autoLongPressSpeed,
                  onChanged: _busy
                      ? null
                      : (value) => _update(
                          preferences.copyWith(autoLongPressSpeed: value),
                        ),
                ),
                const SizedBox(height: 16),
                const Text('切换剧集时的倍速'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('gesture-episode-speed-lock-keep'),
                      label: const Text('保持倍速锁定'),
                      selected: preferences.keepSpeedLockAcrossEpisodes,
                      onSelected: _busy
                          ? null
                          : (_) => _update(
                              preferences.copyWith(
                                keepSpeedLockAcrossEpisodes: true,
                              ),
                            ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('gesture-episode-speed-lock-reset'),
                      label: const Text('恢复正常倍速'),
                      selected: !preferences.keepSpeedLockAcrossEpisodes,
                      onSelected: _busy
                          ? null
                          : (_) => _update(
                              preferences.copyWith(
                                keepSpeedLockAcrossEpisodes: false,
                              ),
                            ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    '保持倍速锁定：切换上/下一集后继续以锁定的倍速（如长按锁定的 2 倍）播放；恢复正常倍速：切换后解除锁定，回到默认倍速。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '提示：手势仅在播放画面内生效；滑动到屏幕顶部左右角落松开手指可取消本次进度拖动。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final info = await widget.repository.storage();
      if (mounted) {
        setState(() {
          _info = info;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _move() async {
    String? parent;
    if (Platform.isAndroid || Platform.isIOS) {
      final support = await getApplicationSupportDirectory();
      final directories = <String, String>{support.path: '应用内部存储'};
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectories() ?? [];
        for (var i = 0; i < external.length; i++) {
          directories[external[i].path] =
              i == 0 ? '设备共享存储（应用目录）' : 'SD 卡 ${i + 1}（应用目录）';
        }
      } else {
        final documents = await getApplicationDocumentsDirectory();
        directories[documents.path] = '文件 App 可见目录';
      }
      if (!mounted) return;
      parent = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择下载位置'),
          children: [
            for (final entry in directories.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      );
    } else {
      parent = await FilePicker.getDirectoryPath(dialogTitle: '选择下载保存位置');
    }
    if (parent == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移已下载内容？'),
        content: Text(
          '将视频、合并成品及导出内容迁移到：\n$parent\n\n下载会先暂停，复制成功后清理旧目录。请保证目标有足够空间，并在完成后继续下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.moveDownloads(parent);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('下载目录与空间')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_info != null) ...[
                    Text(
                      '已使用 ${storageSize((_info!['bytes'] as num?)?.toInt() ?? 0)}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '剩余 ${storageSize((_info!['free'] as num?)?.toInt() ?? -1)} · ${_info!['files'] ?? 0} 个文件',
                    ),
                    const SizedBox(height: 24),
                    const Text('当前下载目录'),
                    const SizedBox(height: 8),
                    SelectableText(_info!['directory'] as String? ?? ''),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                            text: _info!['directory'] as String? ?? ''),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('复制路径'),
                    ),
                    const SizedBox(height: 20),
                    const Text('在下载页删除不需要的分集，在本地媒体页删除合并成品或 Emby 导出，可释放空间。'),
                  ],
                  if (_busy || (_info == null && _error == null))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: LinearProgressIndicator(),
                    ),
                  if (_busy) const Text('正在迁移，请保持应用运行…'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_error!),
                    ),
                  if (widget.store.profile.admin)
                    FilledButton.icon(
                      onPressed: _busy ? null : _move,
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: const Text('更改并迁移目录'),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text('刷新用量'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
