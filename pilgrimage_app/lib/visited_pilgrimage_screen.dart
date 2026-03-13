//ここでは聖地の制覇記録をしている。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'firebase_service.dart';
import 'models/location.dart';
import 'models/visited_work_group.dart';
import 'service/location_search_service.dart';
import 'service/visited_spots_store.dart';
import 'widgets/app_ui.dart';
import 'widgets/dialogs.dart';

class VisitedPilgrimageScreen extends StatefulWidget {
  const VisitedPilgrimageScreen({super.key});

  @override
  State<VisitedPilgrimageScreen> createState() =>
      _VisitedPilgrimageScreenState();
}

class _VisitedPilgrimageScreenState extends State<VisitedPilgrimageScreen> {
  static const Color _completedAccentColor = Color(0xFFE2508A);
  static const Color _defaultAccentColor = Color(0xFF1E456E);
  static const Color _completedBackgroundColor = Color(0xFFFFE3EC);
  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(12, 12, 12, 24);

  final TextEditingController _searchCtrl = TextEditingController();
  final LocationSearchService _locationSearchService =
      const LocationSearchService();
  final VisitedSpotsStore _visitedSpotsStore = VisitedSpotsStore();
  late final Stream<List<LocationData>> _locationsStream;

  Set<String> _visitedIds = <String>{};
  bool _visitedLoaded = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _locationsStream = FirebaseService().locationsStreamAllWorks();
    _loadVisitedIds();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVisitedIds() async {
    try {
      final visitedIds = await _visitedSpotsStore.loadVisitedIds();
      if (!mounted) return;
      setState(() {
        _visitedIds = visitedIds;
        _visitedLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _visitedLoaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAppMessageDialog(context, '訪問記録の読み込みに失敗しました');
      });
    }
  }

  Future<void> _toggleVisited(LocationData location, bool nextValue) async {
    final previousIds = Set<String>.from(_visitedIds);
    final updatedIds = Set<String>.from(_visitedIds);

    if (nextValue) {
      updatedIds.add(location.id);
    } else {
      updatedIds.remove(location.id);
    }

    setState(() {
      _visitedIds = updatedIds;
    });

    try {
      await _visitedSpotsStore.saveVisitedIds(updatedIds);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _visitedIds = previousIds;
      });
      await showAppMessageDialog(context, '訪問記録の保存に失敗しました');
    }
  }

  bool _isVisited(LocationData location) => _visitedIds.contains(location.id);

  void _updateQuery(String value) {
    setState(() {
      _query = value;
    });
  }

  ObstructingPreferredSizeWidget _buildAppBar() {
    return CupertinoNavigationBar(
      automaticallyImplyLeading: false,
      leading: const AppBackButton(),
      backgroundColor: Theme.of(context).colorScheme.primary,
      automaticBackgroundVisibility: false,
      middle: SizedBox(
        width: double.infinity,
        child: CupertinoSearchTextField(
          controller: _searchCtrl,
          backgroundColor: CupertinoColors.white,
          placeholder: '作品名・スポット名・住所',
          autocorrect: false,
          onChanged: _updateQuery,
          onSuffixTap: () {
            _searchCtrl.clear();
            _updateQuery('');
          },
        ),
      ),
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [ModeSwitchButton(currentMode: AppMode.map), AppMenuButton()],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: _buildAppBar(),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child:
            !_visitedLoaded
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<LocationData>>(
                  stream: _locationsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const _StatusView(message: '聖地データの取得に失敗しました');
                    }

                    if (!snapshot.hasData &&
                        snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final groups = VisitedWorkGroup.build(
                      locations: snapshot.data ?? <LocationData>[],
                      query: _query,
                      searchService: _locationSearchService,
                    );
                    if (groups.isEmpty) {
                      return _StatusView(
                        message:
                            _query.trim().isEmpty
                                ? '聖地データがまだありません'
                                : '検索条件に合う聖地が見つかりませんでした',
                      );
                    }

                    final hasQuery = _query.trim().isNotEmpty;
                    return ListView.separated(
                      padding: _listPadding,
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return _buildWorkGroupCard(group, hasQuery: hasQuery);
                      },
                    );
                  },
                ),
      ),
    );
  }

  Widget _buildWorkGroupCard(VisitedWorkGroup group, {required bool hasQuery}) {
    final completed = group.isCompleted(_visitedIds);
    final visitedCount = group.visitedCount(_visitedIds);
    final accentColor = completed ? _completedAccentColor : _defaultAccentColor;
    final backgroundColor =
        completed ? _completedBackgroundColor : CupertinoColors.white;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Material(
        color: backgroundColor,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey<String>(
              'visited-${group.workTitle}-${hasQuery ? 'search' : 'all'}',
            ),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            initiallyExpanded: hasQuery,
            collapsedBackgroundColor: backgroundColor,
            backgroundColor: backgroundColor,
            iconColor: accentColor,
            collapsedIconColor: accentColor,
            leading: Icon(
              completed ? Icons.folder_special : Icons.folder_outlined,
              color: accentColor,
            ),
            title: Text(
              '${group.workTitle} [${group.allSpots.length}]',
              style: TextStyle(color: accentColor, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '$visitedCount / ${group.allSpots.length} 制覇',
              style: TextStyle(
                color:
                    completed
                        ? accentColor
                        : CupertinoColors.systemGrey.darkColor,
                fontWeight: completed ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            children: group.visibleSpots
                .map((spot) => _buildSpotTile(spot, accentColor))
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  Widget _buildSpotTile(LocationData spot, Color accentColor) {
    final visited = _isVisited(spot);
    final subtitle = spot.detailText;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 12, 0),
      leading: Text(
        '|-',
        style: TextStyle(color: accentColor, fontWeight: FontWeight.w700),
      ),
      title: Text(
        spot.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: visited ? TextDecoration.lineThrough : null,
          color: visited ? accentColor : CupertinoColors.black,
        ),
      ),
      subtitle:
          subtitle.isEmpty
              ? null
              : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Checkbox.adaptive(
        value: visited,
        activeColor: const Color(0xFFE2508A),
        onChanged: (value) => _toggleVisited(spot, value ?? false),
      ),
      onTap: () => _toggleVisited(spot, !visited),
    );
  }
}

class _StatusView extends StatelessWidget {
  final String message;

  const _StatusView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: CupertinoColors.systemGrey,
          ),
        ),
      ),
    );
  }
}
