import 'catalog_sort.dart';
import 'models.dart';

List<SourceSite> followedSources(List<Drama> dramas) => [
  for (final site in SourceSite.values)
    if (dramas.any((drama) => drama.source == site.id)) site,
];

bool matchesFollowTitle(Drama drama, String query) =>
    matchesTitle(drama.title, query);
