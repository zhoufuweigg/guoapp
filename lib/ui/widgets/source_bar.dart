import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'bar_button.dart';
import 'page_header.dart';
import 'search_field.dart';

class SourceBar extends StatelessWidget {
  const SourceBar({
    super.key,
    required this.source,
    required this.onSwitchSource,
    required this.onOpenSearch,
    required this.onSearchSubmitted,
    this.searchController,
    this.televisionLeading,
    this.actions = const [],
  });
  final String source;
  final void Function(BuildContext anchor) onSwitchSource;
  final VoidCallback onOpenSearch;
  final ValueChanged<String> onSearchSubmitted;
  final TextEditingController? searchController;
  final Widget? televisionLeading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final form = AppScope.formFactorOf(context);
    final hint = '在 $source 中搜索';
    final switcher = Builder(
      builder: (anchor) => BarButton(
        icon: Icons.public_rounded,
        tooltip: '切换站源',
        onPressed: () => onSwitchSource(anchor),
      ),
    );
    final search = BarButton(
      icon: Icons.search_rounded,
      tooltip: hint,
      onPressed: onOpenSearch,
    );
    return switch (form) {
      FormFactor.phone => PageHeader(
        title: source,
        actions: [switcher, search, ...actions],
      ),
      FormFactor.pad || FormFactor.window => PageHeader(
        title: source,
        actions: [
          switcher,
          const SizedBox(width: 4),
          SizedBox(
            width: MediaQuery.sizeOf(context).width >= 900 ? 320 : 240,
            child: SearchField(
              hint: hint,
              controller: searchController,
              onSubmitted: onSearchSubmitted,
            ),
          ),
          const SizedBox(width: 4),
          ...actions,
        ],
      ),
      FormFactor.television => SizedBox(
        height: 48,
        child: Row(
          spacing: 10,
          children: [
            ?televisionLeading,
            const Spacer(),
            Text(
              source,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            switcher,
            search,
            ...actions,
          ],
        ),
      ),
    };
  }
}
