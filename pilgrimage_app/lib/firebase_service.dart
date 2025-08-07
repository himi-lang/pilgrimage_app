import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/location.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Firestore内のすべての「聖地」ドキュメントをまとめて取得
  Future<List<LocationData>> fetchLocations() async {
    try {
      // サブコレクション名 "聖地" を collectionGroup で一発取得
      final querySnapshot = await _db.collectionGroup('聖地').get();
      print('◾️ Firestore collectionGroup取得件数: ${querySnapshot.docs.length}');

      // ドキュメントごとに LocationData に変換
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        // 親ドキュメントID（アニメ作品タイトル）は 2階層上のID
        final workTitle = doc.reference.parent.parent?.id ?? '不明な作品';
        final location = LocationData(
          id: doc.id,
          name: data['name'] as String? ?? '',
          address: data['address'] as String? ?? '',
          description: data['description'] as String? ?? '',
          image: data['image'] as String? ?? '',
          latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
          workTitle: workTitle,
        );
        print(
          ' ✅ Firestore→Model: ${location.name} @ ${location.latitude},${location.longitude} (${location.workTitle})',
        );
        return location;
      }).toList();
    } catch (e) {
      print('🔥 Firestore取得エラー: $e');
      return [];
    }
  }
}
