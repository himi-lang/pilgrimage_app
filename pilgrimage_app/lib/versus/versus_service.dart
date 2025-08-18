import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VersusService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String _code6() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String> createRoom({
    bool isPrivate = false,
    String difficulty = 'normal',
  }) async {
    final uid = _auth.currentUser!.uid;
    final ref = _db.collection('rooms').doc();
    final code = isPrivate ? _code6() : '';
    await ref.set({
      'code': code,
      'isPrivate': isPrivate,
      'hostUid': uid,
      'status': 'waiting',
      'createdAt': FieldValue.serverTimestamp(),
      'difficulty': difficulty,
      'round': 0,
      'questions': [],
    });
    await _db
        .collection('rooms')
        .doc(ref.id)
        .collection('players')
        .doc(uid)
        .set({
          'displayName': _auth.currentUser!.displayName ?? 'Player',
          'photoURL': _auth.currentUser!.photoURL,
          'score': 0,
          'joinedAt': FieldValue.serverTimestamp(),
        });
    return ref.id;
  }

  Future<String?> joinByCode(String code) async {
    final q =
        await _db
            .collection('rooms')
            .where('code', isEqualTo: code.toUpperCase())
            .where('status', isEqualTo: 'waiting')
            .limit(1)
            .get();
    if (q.docs.isEmpty) return null;
    final roomId = q.docs.first.id;
    await _addSelf(roomId);
    return roomId;
  }

  Future<String?> quickJoin({String difficulty = 'normal'}) async {
    // いちばん古いwaiting部屋に入る。なければ作成
    final q =
        await _db
            .collection('rooms')
            .where('isPrivate', isEqualTo: false)
            .where('status', isEqualTo: 'waiting')
            .where('difficulty', isEqualTo: difficulty)
            .orderBy('createdAt')
            .limit(1)
            .get();
    if (q.docs.isEmpty) {
      return createRoom(isPrivate: false, difficulty: difficulty);
    }
    final roomId = q.docs.first.id;
    await _addSelf(roomId);
    return roomId;
  }

  Future<void> _addSelf(String roomId) async {
    final uid = _auth.currentUser!.uid;
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('players')
        .doc(uid)
        .set({
          'displayName': _auth.currentUser!.displayName ?? 'Player',
          'photoURL': _auth.currentUser!.photoURL,
          'score': 0,
          'joinedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> startMatch(
    String roomId,
    List<Map<String, dynamic>> questions,
  ) async {
    await _db.collection('rooms').doc(roomId).update({
      'questions': questions,
      'status': 'playing',
      'round': 0,
    });
  }

  Future<void> submitAnswer({
    required String roomId,
    required int roundNo,
    required String answer,
    required int timeMs,
    required bool correct,
  }) async {
    final uid = _auth.currentUser!.uid;
    final id = '${roundNo}_${uid.substring(0, 8)}';
    await _db
        .collection('rooms')
        .doc(roomId)
        .collection('answers')
        .doc(id)
        .set({
          'uid': uid,
          'roundNo': roundNo,
          'answer': answer,
          'correct': correct,
          'timeMs': timeMs,
          'submittedAt': FieldValue.serverTimestamp(),
        });
    if (correct) {
      await _db
          .collection('rooms')
          .doc(roomId)
          .collection('players')
          .doc(uid)
          .update({
            'score': FieldValue.increment(
              1000 - (timeMs / 50).floor().clamp(0, 500),
            ),
          });
    }
  }

  Future<void> nextRound(String roomId, int nextRound) async {
    await _db.collection('rooms').doc(roomId).update({'round': nextRound});
  }
}
