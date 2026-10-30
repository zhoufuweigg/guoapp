import 'package:flutter/material.dart';

import '../../local_profiles.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../settings/settings_rows.dart';
import '../settings/settings_sections.dart';
import '../widgets/focus_ring.dart';
import '../widgets/group_card.dart';
import 'password_dialog.dart';
import 'user_editor.dart';

const maxProfiles = 20;

String profileSummary(LocalProfile profile) {
  if (profile.admin) return '管理员 · 全部权限';
  final sources = [
    for (final site in SourceSite.values)
      if (profile.sources.contains(site.id)) site.name,
  ];
  return '${sources.isEmpty ? '未开放站源' : sources.join(' / ')} · '
      '${profile.download ? '可下载' : '仅在线观看'}';
}

Future<void> switchToProfile(
  BuildContext context,
  LocalStore store,
  LocalProfile profile,
) async {
  if (!profile.protected) {
    await saveSetting(context, () => store.switchProfile(profile.id));
    return;
  }
  await showPasswordDialog(
    context,
    title: '登录 ${profile.name}',
    onSubmit: (pin) => store.switchProfile(profile.id, pin: pin),
  );
}

class UsersView extends StatelessWidget {
  const UsersView({super.key, required this.store, required this.open});
  final LocalStore store;
  final OpenSubpage open;

  void _edit([LocalProfile? profile]) => open(
    profile == null
        ? '添加用户'
        : profile.admin
        ? '编辑管理员'
        : '编辑用户',
    (_) => UserEditor(store: store, profile: profile),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final admin = store.profile.admin;
      final profiles = store.profiles;
      final adminProtected = profiles.firstWhere((p) => p.admin).protected;
      final full = profiles.length >= maxProfiles;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          SettingsCard(
            children: [
              for (final profile in profiles)
                ProfileTile(
                  key: ValueKey('profile-${profile.id}'),
                  profile: profile,
                  subtitle: profileSummary(profile),
                  current: profile.id == store.profile.id,
                  onTap: profile.id == store.profile.id
                      ? null
                      : () => switchToProfile(context, store, profile),
                  trailing: admin
                      ? FocusRing(
                          radius: 20,
                          child: IconButton(
                            tooltip: '编辑 ${profile.name}',
                            onPressed: () => _edit(profile),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        )
                      : null,
                ),
              if (admin)
                SettingsTile(
                  title: '添加用户',
                  subtitle: !adminProtected
                      ? '需要先为管理员设置密码'
                      : full
                      ? '最多 $maxProfiles 个用户'
                      : null,
                  icon: Icons.person_add_alt_rounded,
                  enabled: adminProtected && !full,
                  onTap: _edit,
                ),
            ],
          ),
          SettingsCard(
            children: [
              SwitchTile(
                title: '启动时需要登录',
                subtitle: admin ? '每次打开应用先选择用户并输入密码' : adminOnly,
                value: store.forceLogin,
                onChanged: admin
                    ? (value) =>
                          saveSetting(context, () => store.setForceLogin(value))
                    : null,
              ),
              if (store.profile.protected)
                SettingsTile(
                  title: '锁定当前用户',
                  subtitle: '回到登录页，再次使用需要输入密码',
                  trailing: const Icon(Icons.lock_outline_rounded),
                  onTap: store.lock,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '各用户的追剧和观看记录独立保存，下载文件由本机共享。轻点用户即可切换，有密码的用户需要先验证。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.profile,
    required this.subtitle,
    this.current = false,
    this.onTap,
    this.trailing,
    this.autofocus = false,
  });
  final LocalProfile profile;
  final String subtitle;
  final bool current;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return TileFocus(
      builder: (focusNode) => ListTile(
        focusNode: focusNode,
        minTileHeight: 68,
        contentPadding: EdgeInsets.fromLTRB(
          20,
          4,
          trailing == null ? 20 : 12,
          4,
        ),
        horizontalTitleGap: 16,
        autofocus: autofocus,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: current
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_outline_rounded,
            size: 22,
            color: current
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
        title: Row(
          spacing: 8,
          children: [
            Flexible(
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (current)
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '当前',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            if (profile.protected)
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
                semanticLabel: '有密码',
              ),
          ],
        ),
        subtitle: Text(subtitle),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
