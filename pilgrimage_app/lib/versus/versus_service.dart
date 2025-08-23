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
      'roundTimeSec': 20,
      'questions': [],
      'roundStartedAt': null,
    });
    await ref.collection('players').doc(uid).set({
      'displayName': _auth.currentUser!.displayName ?? 'Player',
      'photoURL': _auth.currentUser!.photoURL,
      'score': 0,
      'streak': 0,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<String?> joinByCode(String code) async {
    final q =
        await _db
            .collection('rooms')
            .where('code', isEqualTo: code.trim().toUpperCase())
            .where('status', isEqualTo: 'waiting')
            .limit(1)
            .get();
    if (q.docs.isEmpty) return null;
    final roomId = q.docs.first.id;
    await _addSelf(roomId);
    return roomId;
  }

  Future<String?> quickJoin({String difficulty = 'normal'}) async {
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
          'score': FieldValue.increment(0),
          'streak': FieldValue.increment(0),
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// 開始：ホスト以外は明示的にエラーにする（UIで原因が出る）
  Future<void> startMatch(
    String roomId,
    List<Map<String, dynamic>> questions,
  ) async {
    final uid = _auth.currentUser!.uid;
    final roomRef = _db.collection('rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      final data = snap.data() ?? {};
      if (data['hostUid'] != uid) {
        throw StateError('host-only'); // ルールで落ちる前に明示
      }
      tx.update(roomRef, {
        'questions': questions,
        'status': 'playing',
        'round': 0,
        'roundStartedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// 次ラウンド：ホストチェック＋開始時刻を更新
  Future<void> nextRound(String roomId, int nextRound) async {
    final uid = _auth.currentUser!.uid;
    final roomRef = _db.collection('rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      final data = snap.data() ?? {};
      if (data['hostUid'] != uid) {
        throw StateError('host-only');
      }
      tx.update(roomRef, {
        'round': nextRound,
        'roundStartedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// 回答送信（冪等化）：answers が既にあればスコア加算しない
  Future<void> submitAnswer({
    required String roomId,
    required int roundNo,
    required String answer,
    required int timeMs,
    required bool correct,
  }) async {
    final uid = _auth.currentUser!.uid;
    final roomRef = _db.collection('rooms').doc(roomId);
    final playerRef = roomRef.collection('players').doc(uid);
    final ansRef = roomRef
        .collection('answers')
        .doc('${roundNo}_${uid.substring(0, 8)}');

    await _db.runTransaction((tx) async {
      // 既回答チェック（同ラウンド重複を無効化）
      final existed = await tx.get(ansRef);
      if (existed.exists) return;

      final roomSnap = await tx.get(roomRef);
      final diff = (roomSnap.data()?['difficulty'] ?? 'normal') as String;
      final mult = {'easy': 1.0, 'normal': 1.25, 'hard': 1.5}[diff] ?? 1.0;

      final playerSnap = await tx.get(playerRef);
      final curStreak = (playerSnap.data()?['streak'] ?? 0) as int;

      tx.set(ansRef, {
        'uid': uid,
        'roundNo': roundNo,
        'answer': answer,
        'correct': correct,
        'timeMs': timeMs,
        'submittedAt': FieldValue.serverTimestamp(),
      });

      if (correct) {
        final speed = (1000 - (timeMs ~/ 50)).clamp(0, 500); // 0..500
        final base = 300;
        final bonus = curStreak * 50;
        final inc = ((base + speed + bonus) * mult).round();
        tx.update(playerRef, {
          'score': FieldValue.increment(inc),
          'streak': curStreak + 1,
        });
      } else {
        tx.update(playerRef, {'streak': 0});
      }
    });
  }

  /// 退出：最古参へホスト移譲 or 参加者0なら部屋削除（トランザクション）
  /// 退出：最古参へホスト移譲 or 0人なら削除（書き順とクエリ位置を安全化）
  Future<void> leaveRoom(String roomId) async {
    final uid = _auth.currentUser!.uid;
    final roomRef = _db.collection('rooms').doc(roomId);
    final playerRef = roomRef.collection('players').doc(uid);

    // 1) まず自分を削除（単発書き込み。ここはトランザクション不要）
    try {
      await playerRef.delete();
    } catch (_) {
      // 既に消えていても続行
    }

    // 2) 残存プレイヤーを取得（トランザクション外のクエリでOK）
    final restSnap =
        await roomRef.collection('players').orderBy('joinedAt').limit(1).get();

    // 3) 0人なら部屋削除
    if (restSnap.docs.isEmpty) {
      try {
        await roomRef.delete();
      } catch (_) {}
      return;
    }

    // 4) ホストが自分だったら移譲（この更新だけ原子的に）
    await _db.runTransaction((tx) async {
      final room = await tx.get(roomRef);
      final hostUid = room.data()?['hostUid'] as String?;
      if (hostUid == uid) {
        tx.update(roomRef, {'hostUid': restSnap.docs.first.id});
      }
    });
  }
}
