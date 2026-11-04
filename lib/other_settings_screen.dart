import 'package:flutter/material.dart';

import 'local_store.dart';
import 'playback_preferences.dart';
import 'widgets.dart';

/// 「其他设置」：暂不归入播放/手势、下载、主题等既有分组的杂项功能。
class OtherSettingsScreen extends StatefulWidget {
  const OtherSettingsScreen({super.key, required this.store});
  final LocalStore store;
  @override
  State<OtherSettingsScreen> createState() => _OtherSettingsScreenState();
}

class _OtherSettingsScreenState extends State<OtherSettingsScreen> {
  bool _busy = false;

  Future<void> _update(PlaybackPreferences next) async {
    setState(() => _busy = true);
    try {
      await widget.store.setPlaybackPreferences(next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearProgress() async {
    final count = widget.store.catalogProgress.length;
    if (count == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂无已保存的浏览进度')));
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除浏览进度'),
        content: Text('将清除 $count 个站源的目录浏览断点，且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await saveUserChange(context, widget.store.clearCatalogProgress);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已清除全部浏览进度')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清除失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('其他设置')),
    body: AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final preferences = widget.store.playbackPreferences;
        final progressCount = widget.store.catalogProgress.length;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('other-save-catalog-progress'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('保存浏览进度'),
                  subtitle: const Text(
                    '记录每个站源、每个分类（如红果下的推荐 / 真人剧 / 漫剧 / AI 剧）里刷到的位置；'
                    '再次进入该分类时自动从断点继续往下刷。'
                    '浏览进度会随配置备份（含 WebDAV）一起备份与恢复。',
                  ),
                  value: preferences.saveCatalogProgress,
                  onChanged: _busy
                      ? null
                      : (value) => _update(
                          preferences.copyWith(saveCatalogProgress: value),
                        ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  key: const ValueKey('other-clear-catalog-progress'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('清除全部浏览进度'),
                  subtitle: Text(
                    progressCount == 0
                        ? '当前没有已保存的浏览进度'
                        : '已保存 $progressCount 个浏览断点',
                  ),
                  enabled: !_busy && progressCount > 0,
                  onTap: _clearProgress,
                ),
                const SizedBox(height: 16),
                const Text(
                  '提示：浏览断点按「站源 × 分类」分别记录，恢复时会优先定位到上次的视频；'
                  '若该视频已下架，会自动定位到附近仍在的剧集。',
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
