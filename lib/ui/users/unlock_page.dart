import 'package:flutter/material.dart';

import '../../local_store.dart';
import '../app_scope.dart';
import '../settings/backup_actions.dart';
import '../settings/settings_rows.dart';
import '../widgets/focus_ring.dart';
import 'users_view.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.store});
  final LocalStore store;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  var _busy = false;

  Future<void> _run(Future<String?> Function() task) async {
    setState(() => _busy = true);
    String? message;
    try {
      message = await task();
    } catch (failure) {
      message = failure is StateError ? failure.message : '$failure';
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
    final theme = Theme.of(context);
    final store = widget.store;
    final error = store.configurationError;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppScope.of(context).television
                ? const EdgeInsets.symmetric(
                    horizontal: televisionInset,
                    vertical: 27,
                  )
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 24,
                children: [
                  Icon(
                    Icons.play_circle_fill_rounded,
                    color: theme.colorScheme.primary,
                    size: 72,
                  ),
                  _Heading(
                    title: error == null ? '选择用户' : '需要恢复本地配置',
                    message: error,
                  ),
                  if (error == null)
                    SettingsCard(
                      children: [
                        for (final (index, profile) in store.profiles.indexed)
                          ProfileTile(
                            key: ValueKey('profile-${profile.id}'),
                            profile: profile,
                            subtitle: profile.admin ? '管理员' : '普通用户',
                            autofocus: index == 0,
                            onTap: () =>
                                switchToProfile(context, store, profile),
                          ),
                      ],
                    )
                  else ...[
                    FocusRing(
                      radius: 24,
                      child: FilledButton(
                        autofocus: true,
                        style: _buttonStyle,
                        onPressed: _busy
                            ? null
                            : () =>
                                  _run(() => recoverBackupFile(context, store)),
                        child: const Text('从备份恢复'),
                      ),
                    ),
                    FocusRing(
                      radius: 24,
                      child: OutlinedButton(
                        style: _buttonStyle,
                        onPressed: _busy
                            ? null
                            : () => _run(() => exportRecoveryFile(store)),
                        child: const Text('导出原始配置'),
                      ),
                    ),
                    FocusRing(
                      radius: 24,
                      child: TextButton(
                        style: _buttonStyle,
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await store.reload();
                                return null;
                              }),
                        child: const Text('重新读取'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _buttonStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
  ),
);

class _Heading extends StatelessWidget {
  const _Heading({required this.title, this.message});
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 6,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (message case final message?)
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
      ],
    );
  }
}
