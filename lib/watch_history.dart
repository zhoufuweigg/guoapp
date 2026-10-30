import 'catalog_sort.dart';
import 'models.dart';

enum WatchPeriod {
  today('今天'),
  yesterday('昨天'),
  earlier('更早');

  const WatchPeriod(this.label);
  final String label;

  static WatchPeriod of(DateTime watched, DateTime now) {
    final local = watched.toLocal();
    if (!local.isBefore(DateTime(now.year, now.month, now.day))) return today;
    if (!local.isBefore(DateTime(now.year, now.month, now.day - 1))) {
      return yesterday;
    }
    return earlier;
  }
}

List<SourceSite> watchedSources(List<WatchEntry> history) => [
  for (final site in SourceSite.values)
    if (history.any((entry) => entry.drama.source == site.id)) site,
];

bool matchesWatchTitle(WatchEntry entry, String query) =>
    matchesTitle(entry.drama.title, query);
