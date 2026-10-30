import 'package:flutter/material.dart';

import '../../app_build.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../search/search_page.dart';
import '../settings/sources_view.dart';
import '../shell/app_shell.dart';
import '../widgets/choice_panel.dart';

Future<void> pickSource(BuildContext anchor, LocalStore store) async {
  final value = await showChoicePanel<String>(
    context: anchor,
    title: '全部站源',
    options: [
      for (final source in store.sources) ChoiceOption(source.id, source.name),
    ],
    selected: store.source,
    grid: ChoiceGrid.sources,
    action: allSourcesEnabled
        ? (
            label: '管理站源',
            icon: Icons.tune_rounded,
            onPressed: () => openPage<void>(
              anchor,
              (_) => Scaffold(
                appBar: AppBar(title: const Text('站源管理')),
                body: SourcesView(store: store),
              ),
            ),
          )
        : null,
  );
  if (value == null || value == store.source) return;
  try {
    await store.setCatalogSource(value, allSources: false);
  } catch (_) {
    if (!anchor.mounted) return;
    ScaffoldMessenger.maybeOf(
      anchor,
    )?.showSnackBar(const SnackBar(content: Text('未能切换站源，请重试')));
  }
}

Future<void> openSearch(
  BuildContext context,
  LocalStore store,
  SourceSite source, {
  String query = '',
}) => openPage<void>(
  context,
  (_) => SearchPage(store: store, source: source, query: query),
);
