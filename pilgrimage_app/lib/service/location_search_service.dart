//ここでは検索の正規化や部分一致、絞り込みといった処理を担当している。

import '../models/location.dart';

class LocationSearchService {
  const LocationSearchService();

  String normalize(String value) {
    final runes = value
        .trim()
        .toLowerCase()
        .runes
        .map((r) {
          if (r >= 0xFF01 && r <= 0xFF5E) return r - 0xFEE0; // 全角→半角
          if (r >= 0x30A1 && r <= 0x30F6) return r - 0x60; // カタカナ→ひらがな
          return r;
        })
        .where((r) {
          const droppedRunes = <int>{0x0020, 0x3000, 0x3001, 0x3002};
          return !droppedRunes.contains(r);
        });

    return String.fromCharCodes(runes);
  }

  bool containsQuery(String source, String query) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) return true;
    return containsNormalizedQuery(source, normalizedQuery);
  }

  bool containsNormalizedQuery(String source, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    return normalize(source).contains(normalizedQuery);
  }

  bool matchesLocation(LocationData location, String query) {
    final normalizedQuery = normalize(query);
    return matchesLocationByNormalizedQuery(location, normalizedQuery);
  }

  bool matchesLocationByNormalizedQuery(
    LocationData location,
    String normalizedQuery,
  ) {
    if (normalizedQuery.isEmpty) return true;

    return location.searchableFields.any(
      (field) => containsNormalizedQuery(field, normalizedQuery),
    );
  }

  List<LocationData> filterLocations(
    Iterable<LocationData> locations,
    String query,
  ) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) {
      return locations.toList(growable: false);
    }

    return locations
        .where(
          (location) =>
              matchesLocationByNormalizedQuery(location, normalizedQuery),
        )
        .toList(growable: false);
  }
}
