import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_build.dart';
import '../../app_device.dart';
import '../../download_preferences.dart';
import '../../local_store.dart';
import '../../playback_preferences.dart';
import '../../resource_settings.dart';
import '../../resource_settings_editor.dart';
import '../app_scope.dart';
import '../update_prompt.dart';
import '../users/users_view.dart';
import '../widgets/focus_ring.dart';
import '../widgets/group_card.dart';
import 'appearance_settings.dart';
import 'backup_actions.dart';
import 'diary_view.dart';
import 'settings_rows.dart';
import 'sources_view.dart';
import 'storage_view.dart';

enum SettingsGroup {
  appearance('外观', Icons.palette_outlined),
  playback('播放', Icons.play_arrow_rounded),
  download('下载', Icons.download_rounded),
  sources('站源', Icons.dns_outlined),
  proxy('代理', Icons.language_rounded),
  users('用户', Icons.manage_accounts_outlined),
  about('关于', Icons.info_outline_rounded),
  diagnostics('诊断', Icons.receipt_long_outlined);

  const SettingsGroup(this.label, this.icon);
  final String label;
  final IconData icon;
}

typedef OpenSubpage = void Function(String title, WidgetBuilder body);

const adminOnly = '需要管理员';
const _noDownload = '当前用户没有下载权限';
const _proxyModes = {'auto': '自动', 'direct': '直连', 'manual': '手动代理'};
const _counts = {1: '1', 2: '2', 3: '3', 4: '4', 5: '5', 6: '6'};
const _intervals = [0, 100, 250, 500, 1000, 2000, 3000, 5000];
const _decoders = {
  TelevisionDecoder.optimized: '默认',
  TelevisionDecoder.hardware: '硬解（兼容）',
  TelevisionDecoder.software: '软解（兼容）',
};
const _links = [
  [
    ('GitHub · 重建版', 'https://github.com/Xanerix/guoapp'),
    ('GitHub · 原作者', 'https://github.com/fish2018'),
  ],
  [
    ('Telegram · 交流群组', 'https://t.me/+c9YKHp7FjSk0MjI1'),
    ('Telegram · 更新频道', 'https://t.me/+F9NnQSsMfOU3OTdl'),
  ],
];

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.group,
    required this.store,
    required this.editor,
    required this.open,
  });
  final SettingsGroup group;
  final LocalStore store;
  final ResourceSettingsEditor editor;
  final OpenSubpage open;

  Future<void> _saveResource(BuildContext context, ResourceSettings settings) =>
      saveSetting(context, () => editor.save(settings));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, editor]),
    builder: (context, _) => group == SettingsGroup.appearance
        ? AppearanceSettings(store: store)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: switch (group) {
              SettingsGroup.playback => _playback(context),
              SettingsGroup.download => _download(context),
              SettingsGroup.sources => _sources(context),
              SettingsGroup.proxy => _proxy(context),
              SettingsGroup.users => [UsersView(store: store, open: open)],
              SettingsGroup.about => _about(context),
              SettingsGroup.diagnostics => _diagnostics(),
              _ => const [],
            },
          ),
  );

  Widget? _editorError() => switch (editor.error) {
    final error? => SettingsTile(
      title: '无法读取网络与下载设置',
      subtitle: error,
      trailing: const Icon(Icons.refresh_rounded),
      onTap: editor.load,
    ),
    null => null,
  };

  List<Widget> _playback(BuildContext context) {
    final preferences = store.playbackPreferences;
    final television = AppScope.of(context).television;
    void savePreferences(PlaybackPreferences next) =>
        saveSetting(context, () => store.setPlaybackPreferences(next));
    return [
      SettingsCard(
        children: [
          ValueTile<double>(
            title: '默认倍速',
            subtitle: '与播放器内设置同步',
            options: {for (final speed in playbackSpeeds) speed: '${speed}x'},
            value: preferences.speed,
            onChanged: (speed) =>
                savePreferences(preferences.copyWith(speed: speed)),
          ),
          ValueTile<int>(
            title: '默认清晰度',
            subtitle: '指定清晰度不可用时，使用源站可用画质',
            options: {
              for (final quality in {
                ...DownloadPreferences.qualities,
                preferences.quality,
              }.toList()..sort((a, b) => b - a))
                quality: quality == 0 ? '自动（优先高清）' : '${quality}P',
            },
            value: preferences.quality,
            onChanged: (quality) =>
                savePreferences(preferences.copyWith(quality: quality)),
          ),
        ],
      ),
      SettingsCard(
        children: [
          ValueTile<TelevisionDecoder>(
            title: '解码方式',
            subtitle: '有声音没画面或卡顿时可换兼容方式，下次打开视频时生效',
            options: _decoders,
            value: preferences.televisionDecoder,
            onChanged: (decoder) => savePreferences(
              preferences.copyWith(televisionDecoder: decoder),
            ),
          ),
          if (Platform.isAndroid) const _RenderingTile(),
          SwitchTile(
            title: '预开下一集',
            subtitle: '提前打开下一集的播放器，切集无需等待',
            value: preferences.preopens(television: television),
            onChanged: (value) =>
                savePreferences(preferences.copyWith(preopen: value)),
          ),
        ],
      ),
      if ((Platform.isAndroid || Platform.isIOS) && !television)
        SettingsCard(
          children: [
            SwitchTile(
              title: '双击快退/快进',
              subtitle: '左侧双击快退，右侧双击快进，关闭时均为暂停',
              value: preferences.doubleTapSeek,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(doubleTapSeek: value)),
            ),
            SwitchTile(
              title: '滑动调节亮度/音量',
              subtitle: '左侧上下滑动调整亮度，右侧上下滑动调整音量',
              value: preferences.swipeLevels,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(swipeLevels: value)),
            ),
          ],
        ),
      if (Platform.isAndroid && !television)
        SettingsCard(
          children: [
            SwitchTile(
              title: '离开应用时自动小窗',
              subtitle: '播放中回到桌面时自动进入画中画',
              value: preferences.autoPictureInPicture,
              onChanged: (value) => savePreferences(
                preferences.copyWith(autoPictureInPicture: value),
              ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _download(BuildContext context) {
    final canDownload = store.canDownload;
    final admin = store.profile.admin;
    final preferences = store.downloadPreferences;
    final settings = editor.settings;
    final editable = settings != null && !editor.saving;
    void savePreferences(DownloadPreferences next) =>
        saveSetting(context, () => store.setDownloadPreferences(next));
    return [
      SettingsCard(
        children: [
          ValueTile<int>(
            title: '默认画质',
            subtitle: canDownload ? '指定画质不可用时，使用源站可用画质' : _noDownload,
            options: {
              for (final quality in DownloadPreferences.qualities)
                quality: quality == 0 ? '自动（优先高清）' : '${quality}P',
            },
            value: preferences.quality,
            onChanged: canDownload
                ? (quality) =>
                      savePreferences(preferences.copyWith(quality: quality))
                : null,
          ),
          SwitchTile(
            title: '默认包含 VIP 集',
            subtitle: canDownload ? 'VIP 集可能仅提供试看内容，下载前仍可调整选择' : _noDownload,
            value: preferences.includeVip,
            onChanged: canDownload
                ? (value) =>
                      savePreferences(preferences.copyWith(includeVip: value))
                : null,
          ),
          SettingsTile(
            title: '目录与空间',
            subtitle: canDownload ? '查看存储用量、迁移已下载文件' : _noDownload,
            enabled: canDownload,
            onTap: () => open('目录与空间', (_) => StorageView(store: store)),
          ),
        ],
      ),
      SettingsCard(
        children: [
          ?_editorError(),
          ValueTile<int>(
            title: '同时下载数量',
            subtitle: admin ? null : adminOnly,
            options: _counts,
            value: settings?.downloadConcurrency,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(downloadConcurrency: value),
                  )
                : null,
          ),
          SwitchTile(
            title: '按站源分类保存',
            subtitle: admin ? '新任务放入各站源的子目录，已有下载继续使用原位置' : adminOnly,
            value: settings?.downloadBySource ?? false,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(downloadBySource: value),
                  )
                : null,
          ),
        ],
      ),
      if (Platform.isIOS) const _Note('iOS 下载和媒体处理需要保持应用在前台；切到后台会暂停，回到前台后可继续。'),
    ];
  }

  List<Widget> _sources(BuildContext context) {
    final settings = editor.settings;
    final editable = settings != null && !editor.saving;
    return [
      if (allSourcesEnabled)
        SettingsCard(
          children: [
            SettingsTile(
              title: '站源管理',
              subtitle: '开启或关闭站源',
              onTap: () => open('站源管理', (_) => SourcesView(store: store)),
            ),
          ],
        ),
      SettingsCard(
        children: [
          ?_editorError(),
          ValueTile<int>(
            title: '目录请求间隔',
            subtitle: store.profile.admin ? '同一站源两次请求之间的最短间隔' : adminOnly,
            options: {
              for (final interval in {
                ..._intervals,
                ?settings?.catalogIntervalMs,
              }.toList()..sort())
                interval: '$interval 毫秒',
            },
            value: settings?.catalogIntervalMs,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(catalogIntervalMs: value),
                  )
                : null,
          ),
        ],
      ),
    ];
  }

  List<Widget> _proxy(BuildContext context) {
    final admin = store.profile.admin;
    final settings = editor.settings;
    final editable = settings != null && !editor.saving;
    final mode = settings?.proxyMode;
    return [
      if (settings != null && settings.warning.isNotEmpty)
        _Note(settings.warning),
      SettingsCard(
        children: [
          ?_editorError(),
          ValueTile<String>(
            title: '连接方式',
            subtitle: !admin
                ? adminOnly
                : switch (mode) {
                    'auto' when settings!.systemProxyStatus.isNotEmpty =>
                      settings.systemProxyStatus,
                    'auto' => '使用系统静态代理；未配置时使用环境变量或直连',
                    _ => null,
                  },
            options: _proxyModes,
            value: mode,
            onChanged: editable
                ? (value) => value == 'manual'
                      ? _editProxy(context, settings)
                      : _saveResource(
                          context,
                          settings.copyWith(proxyMode: value),
                        )
                : null,
          ),
          if (mode == 'manual')
            SettingsTile(
              title: '代理地址',
              subtitle: '支持 HTTP、HTTPS、SOCKS5；仅保存在本机，不进入配置备份',
              value: settings!.proxyUrl.isEmpty ? '未设置' : '已设置',
              enabled: editable,
              onTap: () => _editProxy(context, settings),
            ),
        ],
      ),
    ];
  }

  Future<void> _editProxy(
    BuildContext context,
    ResourceSettings settings,
  ) async {
    final address = await showDialog<String>(
      context: context,
      builder: (_) => _ProxyDialog(initial: settings.proxyUrl),
    );
    if (address == null || !context.mounted) return;
    await _saveResource(
      context,
      settings.copyWith(proxyMode: 'manual', proxyUrl: address),
    );
  }

  List<Widget> _about(BuildContext context) {
    final version = AppScope.of(context).version;
    return [
      SettingsCard(
        children: [
          SettingsTile(
            title: appName,
            value: version.isEmpty ? '版本未知' : '版本 $version',
          ),
          const _UpdateCheckTile(),
          SwitchTile(
            title: '启动时检查更新',
            subtitle: '有新版本时每次启动都会提示，可在提示里忽略此版本',
            value: store.checkUpdates,
            onChanged: (value) =>
                saveSetting(context, () => store.setCheckUpdates(value)),
          ),
          SwitchTile(
            title: '匿名使用统计',
            subtitle: '启动时发送随机编号、版本号、平台和红果鉴 / 真果鉴，用于统计使用人数',
            value: store.shareUsage,
            onChanged: (value) =>
                saveSetting(context, () => store.setShareUsage(value)),
          ),
        ],
      ),
      for (final links in _links)
        SettingsCard(
          children: [
            for (final (title, url) in links)
              SettingsTile(
                title: title,
                subtitle: url.replaceFirst('https://', ''),
                onTap: () => _openLink(context, url),
              ),
          ],
        ),
    ];
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开浏览器，链接已复制')));
    }
  }

  List<Widget> _diagnostics() => [
    SettingsCard(
      children: [
        SettingsTile(
          title: '播放调试日记',
          subtitle: '查看并复制应用运行与播放器的详细事件日志',
          onTap: () => open('播放调试日记', (_) => const DiaryView()),
        ),
      ],
    ),
    _BackupCard(store: store),
  ];
}

class _UpdateCheckTile extends StatefulWidget {
  const _UpdateCheckTile();

  @override
  State<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<_UpdateCheckTile> {
  var _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await checkUpdateManually(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsTile(
    title: '检查更新',
    value: _busy ? '检查中' : null,
    enabled: !_busy,
    onTap: _check,
  );
}

class _BackupCard extends StatefulWidget {
  const _BackupCard({required this.store});
  final LocalStore store;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  var _busy = false;

  Future<void> _run(Future<String?> Function() task) async {
    setState(() => _busy = true);
    String? message;
    try {
      message = await task();
    } catch (failure) {
      message = '$failure';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.store.profile.admin;
    return SettingsCard(
      children: [
        SettingsTile(
          title: '导出备份',
          subtitle: admin ? '包含本地用户、追剧、历史和设置，不含视频文件' : adminOnly,
          enabled: admin && !_busy,
          onTap: () => _run(() => exportBackupFile(widget.store)),
        ),
        SettingsTile(
          title: '恢复备份',
          subtitle: admin ? '替换本机的用户、追剧、观看记录和偏好设置，已下载视频保留' : adminOnly,
          enabled: admin && !_busy,
          onTap: () => _run(() => restoreBackupFile(context, widget.store)),
        ),
      ],
    );
  }
}

class _RenderingTile extends StatefulWidget {
  const _RenderingTile();

  @override
  State<_RenderingTile> createState() => _RenderingTileState();
}

class _RenderingTileState extends State<_RenderingTile> {
  bool? _compatible;

  @override
  void initState() {
    super.initState();
    AppDevice.compatibleRendering().then((value) {
      if (mounted) setState(() => _compatible = value);
    });
  }

  Future<void> _switch(bool enabled) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(enabled ? '开启兼容渲染模式？' : '关闭兼容渲染模式？'),
        content: const Text('需要重启应用才能生效，正在进行的下载会中断。'),
        actions: [
          FocusRing(
            radius: 20,
            child: TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
          ),
          FocusRing(
            radius: 20,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('立即重启'),
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (!await AppDevice.setCompatibleRendering(enabled) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('兼容渲染模式未能保存，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => SwitchTile(
    title: '兼容渲染模式',
    subtitle: '改用 Skia 渲染（关闭 Impeller），用于换了解码方式仍没有画面的设备',
    value: _compatible ?? false,
    onChanged: _compatible == null ? null : _switch,
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog({required this.initial});
  final String initial;

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final _address = TextEditingController(text: widget.initial);
  var _visible = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final address = _address.text.trim();
    if (address.isNotEmpty) Navigator.pop(context, address);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('代理地址'),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _address,
        autofocus: true,
        obscureText: !_visible,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: TextInputType.url,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'http://127.0.0.1:7890',
          helperText: '支持 HTTP、HTTPS、SOCKS5',
          suffixIcon: IconButton(
            tooltip: _visible ? '隐藏代理地址' : '显示代理地址',
            onPressed: () => setState(() => _visible = !_visible),
            icon: Icon(
              _visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
      ),
    ),
    actions: [
      FocusRing(
        radius: 20,
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
      FocusRing(
        radius: 20,
        child: FilledButton(onPressed: _submit, child: const Text('保存')),
      ),
    ],
  );
}
