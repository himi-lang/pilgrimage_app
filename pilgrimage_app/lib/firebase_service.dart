// firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/location.dart';

class FirebaseService {
  final _db = FirebaseFirestore.instance;

  // 作品横断で「聖地」を全部ストリーム取得（追加/更新に即追従）
  Stream<List<LocationData>> locationsStreamAllWorks() {
    return _db
        .collectionGroup('聖地')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) {
                final data = d.data();
                return LocationData.fromFirestore(d.reference.path, data);
              }).toList(),
        );
  }

  // 特定作品だけに絞る場合（例：「2.5次元の誘惑」）
  Stream<List<LocationData>> locationsStreamByWork(String workTitle) {
    return _db
        .collection('聖地情報')
        .doc(workTitle)
        .collection('聖地')
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map((d) => LocationData.fromFirestore(d.id, d.data()))
                  .toList(),
        );
  }
}
