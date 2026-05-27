import 'package:shared_preferences/shared_preferences.dart';

class VisitedSpotsStore {
  static const String _visitedSpotIdsKey = 'visited_spot_ids';

  Future<Set<String>> loadVisitedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_visitedSpotIdsKey)?.toSet() ?? <String>{};
  }

  Future<void> saveVisitedIds(Set<String> visitedIds) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedIds = visitedIds.toList()..sort();
    await prefs.setStringList(_visitedSpotIdsKey, sortedIds);
  }
}
