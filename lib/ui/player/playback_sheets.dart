import 'package:flutter/material.dart';

import '../../playback_preferences.dart';
import '../../playback_session.dart';
import '../theme/app_theme.dart';

ThemeData playerTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme
      : AppTheme.build(
          theme.colorScheme.primary,
          Brightness.dark,
          television: false,
        );
}

Future<void> showPlayerSheet(
  BuildContext context,
  WidgetBuilder builder, {
  bool dark = true,
}) {
  final theme = dark ? playerTheme(context) : Theme.of(context);
  final height = MediaQuery.sizeOf(context).height * .6;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surfaceContainerLow,
    constraints: BoxConstraints.tightFor(height: height),
    builder: (context) => Theme(
      data: theme,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: theme.colorScheme.onSurface),
        child: Builder(builder: builder),
      ),
    ),
  );
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(spacing: 8, children: children),
    ),
  );
}

const sheetTitle = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);

class PlaybackSettings extends StatelessWidget {
  const PlaybackSettings({
    super.key,
    required this.session,
    required this.onFailure,
    this.onMiniWindow,
  });
  final PlaybackSession session;
  final VoidCallback onFailure;
  final VoidCallback? onMiniWindow;

  Future<void> _change(Future<void> Function() change) async {
    try {
      await change();
    } catch (_) {
      onFailure();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final label = TextStyle(fontSize: 14, color: colors.onSurfaceVariant);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            children: [
              const Expanded(child: Text('播放设置', style: sheetTitle)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                tooltip: '关闭',
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text('倍速', style: label),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final speed in playbackSpeeds)
                      _Choice(
                        label: '${speed}x',
                        selected: speed == session.speed,
                        onSelected: () =>
                            _change(() => session.setSpeed(speed)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('清晰度', style: label),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: session.local
                      ? [
                          _Choice(
                            label: session.qualityLabel,
                            selected: true,
                            onSelected: null,
                          ),
                        ]
                      : [
                          for (final quality in [...session.qualities, 0])
                            _Choice(
                              label: quality == 0
                                  ? (session.quality == 0
                                        ? session.qualityLabel
                                        : '自动')
                                  : '${quality}P',
                              selected: quality == session.quality,
                              onSelected: session.ready
                                  ? () => _change(
                                      () => session.setQuality(quality),
                                    )
                                  : null,
                            ),
                        ],
                ),
                if (session.danmakuSupported) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('弹幕'),
                    value: session.danmakuEnabled,
                    onChanged: (_) => _change(session.toggleDanmaku),
                  ),
                ],
                if (onMiniWindow case final onMiniWindow?)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.picture_in_picture_alt_rounded),
                    title: const Text('小窗播放'),
                    onTap: onMiniWindow,
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    shape: const StadiumBorder(),
    onSelected: onSelected == null ? null : (_) => onSelected!(),
  );
}
