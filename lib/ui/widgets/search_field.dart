import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../native_text_input.dart';
import '../app_scope.dart';
import 'letter_keyboard.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onSubmitted,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.autofocus = false,
    this.height = 40,
    this.letterKeyboard = false,
    this.matches,
  });
  final String hint;
  final ValueChanged<String> onSubmitted;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final double height;
  final bool letterKeyboard;
  final TitleMatches? matches;

  InputDecoration _decoration(ColorScheme colors) {
    final radius = BorderRadius.circular(height / 2);
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: colors.surfaceContainerHigh,
      contentPadding: EdgeInsets.zero,
      prefixIcon: Icon(
        Icons.search_rounded,
        size: 20,
        color: colors.onSurfaceVariant,
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = _decoration(Theme.of(context).colorScheme);
    final television = AppScope.of(context).television;
    return SizedBox(
      height: height,
      child:
          television &&
              (letterKeyboard ||
                  defaultTargetPlatform == TargetPlatform.android)
          ? _TelevisionSearchField(
              decoration: decoration,
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              letters: letterKeyboard,
              matches: matches,
            )
          : TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: decoration,
            ),
    );
  }
}

class _TelevisionSearchField extends StatefulWidget {
  const _TelevisionSearchField({
    required this.decoration,
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.onSubmitted,
    required this.onChanged,
    required this.letters,
    required this.matches,
  });
  final InputDecoration decoration;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool letters;
  final TitleMatches? matches;

  @override
  State<_TelevisionSearchField> createState() => _TelevisionSearchFieldState();
}

class _TelevisionSearchFieldState extends State<_TelevisionSearchField> {
  final _ownController = TextEditingController();
  final _ownFocus = FocusNode();
  var _editing = false;

  TextEditingController get _controller => widget.controller ?? _ownController;
  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void dispose() {
    if (_editing) NativeTextInput.stop();
    _ownController.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (!widget.letters) {
      _edit();
      return;
    }
    final text = await showLetterKeyboard(
      context,
      text: _controller.text,
      matches: widget.matches,
    );
    if (text == null || !mounted) return;
    _controller.text = text;
    widget.onSubmitted(text);
  }

  void _edit() {
    setState(() => _editing = true);
    NativeTextInput.start(
      _controller.text,
      onChanged: (text) {
        if (!mounted) return;
        _controller.text = text;
        widget.onChanged?.call(text);
      },
      onDone: (text, submit) {
        if (!mounted) return;
        setState(() => _editing = false);
        _controller.text = text;
        if (submit) widget.onSubmitted(text);
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_controller, _focus]),
    builder: (context, _) => InkWell(
      focusNode: _focus,
      autofocus: widget.autofocus,
      focusColor: Colors.transparent,
      customBorder: const StadiumBorder(),
      onTap: _open,
      child: InputDecorator(
        decoration: widget.decoration,
        isFocused: _focus.hasFocus,
        isEmpty: _controller.text.isEmpty,
        textAlignVertical: TextAlignVertical.center,
        child: Text.rich(
          TextSpan(
            text: _controller.text,
            children: [
              if (_editing)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    width: 2,
                    height: 16,
                    margin: const EdgeInsets.only(left: 1),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    ),
  );
}
