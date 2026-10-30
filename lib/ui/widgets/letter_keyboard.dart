import 'dart:async';

import 'package:flutter/material.dart';

import 'focus_ring.dart';

typedef TitleMatches = Future<List<String>> Function(String query);

Future<String?> showLetterKeyboard(
  BuildContext context, {
  required String text,
  TitleMatches? matches,
}) => showDialog<String>(
  context: context,
  builder: (_) => _LetterKeyboard(text: text, matches: matches),
);

const _rows = ['ABCDEF', 'GHIJKL', 'MNOPQR', 'STUVWX', 'YZ1234', '567890'];

class _LetterKeyboard extends StatefulWidget {
  const _LetterKeyboard({required this.text, required this.matches});
  final String text;
  final TitleMatches? matches;

  @override
  State<_LetterKeyboard> createState() => _LetterKeyboardState();
}

class _LetterKeyboardState extends State<_LetterKeyboard> {
  late String _text = widget.text;
  List<String> _matches = const [];
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _match();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    super.dispose();
  }

  void _edit(String text) {
    setState(() => _text = text);
    _match();
  }

  void _match() {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _text.trim();
    final matches = widget.matches;
    if (matches == null || query.isEmpty) {
      setState(() => _matches = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final items = await matches(query);
        if (mounted && generation == _generation) {
          setState(() => _matches = items);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      child: SizedBox(
        width: 720,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  _text.isEmpty ? '输入剧名拼音首字母，例如 BDZC' : _text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _text.isEmpty ? colors.onSurfaceVariant : null,
                    letterSpacing: _text.isEmpty ? null : 2,
                  ),
                ),
              ),
              SizedBox(
                height: 328,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 20,
                  children: [
                    SizedBox(width: 360, child: _keyboard()),
                    Expanded(child: _results(theme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyboard() => Column(
    spacing: 8,
    children: [
      for (final (row, keys) in _rows.indexed)
        Expanded(
          child: Row(
            spacing: 8,
            children: [
              for (final (column, key) in keys.split('').indexed)
                Expanded(
                  child: _Key(
                    autofocus: row == 0 && column == 0,
                    onPressed: () => _edit(_text + key),
                    child: Text(
                      key,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      Expanded(
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: _Key(
                onPressed: () => _edit(
                  _text.isEmpty ? _text : _text.substring(0, _text.length - 1),
                ),
                child: const Icon(Icons.backspace_outlined, size: 20),
              ),
            ),
            Expanded(
              child: _Key(onPressed: () => _edit(''), child: const Text('清空')),
            ),
            Expanded(
              child: _Key(
                filled: true,
                onPressed: () => Navigator.pop(context, _text.trim()),
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _results(ThemeData theme) {
    if (_matches.isEmpty) {
      return Center(
        child: Text(
          _text.trim().isEmpty ? '用左侧键盘输入' : '按「确定」搜索「${_text.trim()}」',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final item in _matches)
          TileFocus(
            builder: (focusNode) => ListTile(
              focusNode: focusNode,
              leading: const Icon(Icons.search_rounded),
              title: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, item),
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.onPressed,
    required this.child,
    this.autofocus = false,
    this.filled = false,
  });
  final VoidCallback onPressed;
  final Widget child;
  final bool autofocus;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return FocusRing(
      radius: 10,
      child: SizedBox.expand(
        child: filled
            ? FilledButton(
                autofocus: autofocus,
                style: style,
                onPressed: onPressed,
                child: child,
              )
            : FilledButton.tonal(
                autofocus: autofocus,
                style: style,
                onPressed: onPressed,
                child: child,
              ),
      ),
    );
  }
}
