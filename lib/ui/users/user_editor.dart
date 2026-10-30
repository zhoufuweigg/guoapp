import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../local_profiles.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../app_scope.dart';
import '../settings/settings_rows.dart';
import '../widgets/focus_ring.dart';
import '../widgets/group_card.dart';

class UserEditor extends StatefulWidget {
  const UserEditor({super.key, required this.store, this.profile});
  final LocalStore store;
  final LocalProfile? profile;

  @override
  State<UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends State<UserEditor> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  late final _sources = {
    ...?widget.profile?.sources,
    if (widget.profile == null)
      for (final site in SourceSite.values) site.id,
  };
  late var _download = widget.profile?.download ?? true;
  var _clearPin = false;
  var _busy = false;
  String? _error;

  LocalProfile? get _profile => widget.profile;
  bool get _admin => _profile?.admin ?? false;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
      if (mounted) await Navigator.maybePop(context);
    } catch (failure) {
      if (mounted) {
        setState(
          () => _error = failure is StateError ? failure.message : '$failure',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() => _run(() async {
    if (!_clearPin && _pin.text != _confirm.text) {
      throw StateError('两次输入的密码不一致');
    }
    await widget.store.saveProfile(
      id: _profile?.id,
      name: _name.text,
      sources: _sources.toList(),
      download: _download,
      pin: _clearPin
          ? ''
          : _pin.text.isEmpty
          ? null
          : _pin.text,
    );
  });

  Future<void> _delete() async {
    final profile = _profile!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${profile.name}？'),
        content: const Text('会同时删除该用户的追剧和观看记录，下载文件保留。'),
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
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => widget.store.deleteProfile(profile.id));
    }
  }

  (String, String) get _pinText {
    final profile = _profile;
    if (profile == null) return ('设置密码（可选）', '不设密码时切换到该用户无需验证');
    if (profile.protected) return ('新密码', '留空保留原密码');
    return ('设置密码', _admin ? '设置后才能添加其他用户' : '不设密码时切换到该用户无需验证');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (pinLabel, pinHint) = _pinText;
    final canClear = _profile?.protected == true && !_admin;
    final pinFields = [
      _Field(
        label: pinLabel,
        controller: _pin,
        hint: '至少 6 位',
        obscure: true,
        enabled: !_clearPin,
      ),
      _Field(
        label: '再次输入密码',
        controller: _confirm,
        obscure: true,
        enabled: !_clearPin,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        GroupCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 20,
                children: [
                  _Field(
                    label: '用户名',
                    controller: _name,
                    hint: '1 至 40 个字符',
                    maxLength: 40,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth >= 456
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 16,
                                children: [
                                  for (final field in pinFields)
                                    Expanded(child: field),
                                ],
                              )
                            : Column(spacing: 20, children: pinFields),
                      ),
                      Text(
                        pinHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (canClear) ...[
          const SizedBox(height: 12),
          GroupCard(
            children: [
              SwitchTile(
                title: '取消此用户密码',
                subtitle: '保存后切换到该用户不再需要验证',
                value: _clearPin,
                onChanged: (value) => setState(() => _clearPin = value),
              ),
            ],
          ),
        ],
        if (!_admin) ...[
          const SizedBox(height: 12),
          GroupCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '允许访问的站源',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '已选 ${SourceSite.values.where((site) => _sources.contains(site.id)).length} 个',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 200).floor().clamp(
                      1,
                      4,
                    );
                    const sites = SourceSite.values;
                    return Column(
                      children: [
                        for (var row = 0; row < sites.length; row += columns)
                          Row(
                            children: [
                              for (var i = row; i < row + columns; i++)
                                Expanded(
                                  child: i < sites.length
                                      ? _SourceCheck(
                                          name: sites[i].name,
                                          value: _sources.contains(sites[i].id),
                                          onChanged: (value) => setState(
                                            () => value
                                                ? _sources.add(sites[i].id)
                                                : _sources.remove(sites[i].id),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GroupCard(
            children: [
              SwitchTile(
                title: '允许下载',
                subtitle: '可下载和管理本机视频；关闭后仅在线观看，下载入口置灰',
                value: _download,
                onChanged: (value) => setState(() => _download = value),
              ),
            ],
          ),
        ],
        if (_admin) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '管理员可以访问全部站源和功能。存在其他用户时不能取消管理员密码。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          spacing: 12,
          children: [
            if (_profile != null && !_admin)
              FocusRing(
                radius: 20,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  onPressed: _busy ? null : _delete,
                  child: const Text('删除用户'),
                ),
              ),
            const Spacer(),
            FocusRing(
              radius: 20,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                ),
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '正在保存…' : '保存'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.enabled = true,
    this.maxLength,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool enabled;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          enableSuggestions: !obscure,
          autocorrect: !obscure,
          inputFormatters: [
            if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
          ],
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _SourceCheck extends StatelessWidget {
  const _SourceCheck({
    required this.name,
    required this.value,
    required this.onChanged,
  });
  final String name;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: FocusRing(
      radius: 24,
      scale: 1,
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusColor: AppScope.of(context).television
              ? Colors.transparent
              : null,
          onTap: () => onChanged(!value),
          child: SizedBox(
            height: 48,
            child: Row(
              spacing: 4,
              children: [
                ExcludeFocus(
                  child: Checkbox(
                    value: value,
                    onChanged: (value) => onChanged(value!),
                  ),
                ),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
