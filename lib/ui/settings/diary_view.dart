import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../diary_service.dart';
import '../widgets/focus_ring.dart';
import '../widgets/status_view.dart';

final _failure = RegExp('err|fail|exception|异常|失败', caseSensitive: false);

class DiaryView extends StatefulWidget {
  const DiaryView({super.key});

  @override
  State<DiaryView> createState() => _DiaryViewState();
}

class _DiaryViewState extends State<DiaryView> {
  final _scroll = ScrollController();
  var _focused = false;

  @override
  void initState() {
    super.initState();
    DiaryService.refreshNativeLogs().whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -120.0,
      LogicalKeyboardKey.arrowDown => 120.0,
      _ => null,
    };
    if (event is KeyUpEvent || step == null || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = _scroll.position;
    if (step < 0 && position.pixels <= 0) return KeyEventResult.ignored;
    _scroll.animateTo(
      (position.pixels + step).clamp(0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
    return KeyEventResult.handled;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: DiaryService.fullText));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日记已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            spacing: 8,
            children: [
              FocusRing(
                radius: 999,
                child: TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制全部'),
                ),
              ),
              FocusRing(
                radius: 999,
                child: TextButton.icon(
                  onPressed: DiaryService.clear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('清空'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: DiaryService.revision,
            builder: (context, _, _) {
              final entries = DiaryService.entries.reversed.toList();
              if (entries.isEmpty) {
                return const StatusView(
                  title: '暂无日记记录',
                  icon: Icons.receipt_long_outlined,
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Focus(
                  onFocusChange: (focused) =>
                      setState(() => _focused = focused),
                  onKeyEvent: (_, event) => _onKey(event),
                  child: Material(
                    color: colors.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: focusVisible(_focused)
                          ? BorderSide(color: colors.onSurface, width: 2)
                          : BorderSide.none,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SelectionArea(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: entries.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            entries[index],
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: _failure.hasMatch(entries[index])
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
