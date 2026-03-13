//ここでは制覇記録で、どれほど制覇したかを調べている。

import '../service/location_search_service.dart';
import 'location.dart';

class VisitedWorkGroup {
  final String workTitle;
  final List<LocationData> allSpots;
  final List<LocationData> visibleSpots;

  const VisitedWorkGroup({
    required this.workTitle,
    required this.allSpots,
    required this.visibleSpots,
  });

  int visitedCount(Set<String> visitedIds) {
    return allSpots.where((spot) => visitedIds.contains(spot.id)).length;
  }

  bool isCompleted(Set<String> visitedIds) {
    return allSpots.isNotEmpty &&
        allSpots.every((spot) => visitedIds.contains(spot.id));
  }

  static List<VisitedWorkGroup> build({
    required List<LocationData> locations,
    required String query,
    required LocationSearchService searchService,
  }) {
    final normalizedQuery = searchService.normalize(query);
    final groupedByWork = <String, List<LocationData>>{};

    for (final location in locations) {
      groupedByWork
          .putIfAbsent(location.displayWorkTitle, () => <LocationData>[])
          .add(location);
    }

    final entries =
        groupedByWork.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return entries
        .map((entry) {
          final allSpots = List<LocationData>.from(entry.value)
            ..sort((a, b) => a.name.compareTo(b.name));
          final workMatches = searchService.containsNormalizedQuery(
            entry.key,
            normalizedQuery,
          );
          final visibleSpots =
              normalizedQuery.isEmpty || workMatches
                  ? allSpots
                  : allSpots
                      .where(
                        (spot) =>
                            searchService.matchesLocationByNormalizedQuery(
                              spot,
                              normalizedQuery,
                            ),
                      )
                      .toList(growable: false);

          return VisitedWorkGroup(
            workTitle: entry.key,
            allSpots: allSpots,
            visibleSpots: visibleSpots,
          );
        })
        .where((group) => group.visibleSpots.isNotEmpty)
        .toList(growable: false);
  }
}
