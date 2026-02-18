import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'map_screen.dart';
import 'widgets/app_ui.dart';

class ImageSearchScreen extends StatefulWidget {
  const ImageSearchScreen({super.key});

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

class _ImageSearchScreenState extends State<ImageSearchScreen> 
{
  String _query = '';
  bool _isGrid = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CupertinoPageScaffold(
      navigationBar: commonAppBar(
        context,
        title: '画像検索モード',
        currentMode: AppMode.map,
        actionsExtra: 
        [
          //IconButton(
          //  tooltip: _isGrid ? 'リスト表示' : 'グリッド表示',
          //  icon: Icon(_isGrid ? Icons.view_agenda : Icons.grid_view),
          //  onPressed: () => setState(() => _isGrid = !_isGrid),
          //),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            // ★ 作品名検索欄
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: CupertinoSearchTextField(
                placeholder: '作品名で検索',
                autocorrect: false,
                onChanged:
                    (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream:
                    FirebaseFirestore.instance
                        .collection('作品一覧フライヤー')
                        .orderBy(FieldPath.documentId)
                        .snapshots(),
                builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '作品一覧の取得に失敗しました\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CupertinoActivityIndicator());
                }

                final docs = snap.data!.docs;

                // ★ 作品名（doc.id）でフィルタ
                final filtered =
                    _query.isEmpty
                        ? docs
                        : docs.where((d) {
                          final title = d.id.toLowerCase();
                          return title.contains(_query);
                        }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('該当する作品がありません'));
                }

                if (_isGrid) {
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _buildCard(context, filtered[index], cs);
                    },
                  );
                } else {
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _buildCard(context, filtered[index], cs);
                    },
                  );
                }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1枚分のカード
  Widget _buildCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    ColorScheme cs,
  ) {
    final title = doc.id; // ドキュメントIDを作品名として使う
    final imageUrl = doc.data()['image'] as String? ?? '';

    return InkWell(
      onTap: () {
        // ★ 画像タップ → MapScreen へ
        Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => MapScreen(initialWorkTitle: title)),
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child:
                  imageUrl.isEmpty
                      ? const Center(child: Icon(Icons.image_not_supported))
                  : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 420,
                        filterQuality: FilterQuality.low,
                        headers: const {'User-Agent': 'Mozilla/5.0'},
                        errorBuilder:
                            (_, __, ___) =>
                                const Center(child: Icon(Icons.broken_image)),
                      ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
