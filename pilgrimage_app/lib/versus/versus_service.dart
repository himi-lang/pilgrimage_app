import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VersusService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;
  User? get user => _auth.currentUser;

  // ========= ロビー系 =========

  /// クイックマッチ。待機中の公開ルームに入る。無ければ作る。
  Future<String> quickJoin({String difficulty = 'normal'}) async {
    final qs =
        await _db
            .collection('rooms')
            .where('isPrivate', isEqualTo: false)
            .where('status', isEqualTo: 'waiting')
            .where('difficulty', isEqualTo: difficulty)
            .orderBy('createdAt', descending: false)
            .limit(5)
            .get();

    String roomId;
    if (qs.docs.isEmpty) {
      roomId = await _createRoomDoc(isPrivate: false, difficulty: difficulty);
    } else {
      roomId = qs.docs.first.id;
    }
    await _joinRoom(roomId);
    return roomId;
  }

  /// ルームを新規作成（プライベート/公開）
  Future<String> createRoom({
    required bool isPrivate,
    String difficulty = 'normal',
  }) async {
    final id = await _createRoomDoc(
      isPrivate: isPrivate,
      difficulty: difficulty,
    );
    await _joinRoom(id);
    return id;
  }

  /// 招待コードで入室（見つからなければ null）
  Future<String?> joinByCode(String code) async {
    final qs =
        await _db
            .collection('rooms')
            .where('code', isEqualTo: code)
            .where('status', isEqualTo: 'waiting')
            .limit(1)
            .get();
    if (qs.docs.isEmpty) return null;
    final id = qs.docs.first.id;
    await _joinRoom(id);
    return id;
  }

  /// ルームから退出
  Future<void> leaveRoom(String roomId) async {
    final u = uid;
    if (u == null) return;
    final ref = _db
        .collection('rooms')
        .doc(roomId)
        .collection('players')
        .doc(u);
    await ref.delete();
  }

  // ========= 対戦進行 =========

  /// 対戦開始（questions セット、answers / rematch をクリア）
  Future<void> startMatch(
    String roomId,
    List<Map<String, dynamic>> questions,
  ) async {
    final room = _db.collection('rooms').doc(roomId);
    await _clearSubcollection(room.collection('answers'));
    await _clearSubcollection(room.collection('rematch'));
    await room.update({
      'status': 'playing',
      'round': 0,
      'questions': questions,
      'roundStartedAt': FieldValue.serverTimestamp(),
      'finishedAt': FieldValue.delete(),
    });
  }

  Future<void> nextRound(String roomId, int round) async {
    await _db.collection('rooms').doc(roomId).update({
      'round': round,
      'roundStartedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> finishMatch(String roomId) async {
    await _db.collection('rooms').doc(roomId).update({
      'status': 'finished',
      'finishedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 解答送信 +（正解なら）スコア加算
  ///
  /// - `answers/{round-uid}` に解答を保存
  /// - すでに正解済みなら**二重加点しない**
  /// - 加点は `players/{uid}.score` へ `FieldValue.increment(points)`
  Future<void> submitAnswer({
    required String roomId,
    required int roundNo,
    required String answer,
    required int timeMs,
    required bool correct,
  }) async {
    final u = uid ?? '';
    final roomRef = _db.collection('rooms').doc(roomId);
    final ansRef = roomRef.collection('answers').doc('$roundNo-$u'); // ラウンド一意
    final playerRef = roomRef.collection('players').doc(u);

    await _db.runTransaction((tx) async {
      final roomSnap = await tx.get(roomRef);
      final ansSnap = await tx.get(ansRef);

      final alreadyCorrect =
          ansSnap.exists
              ? ((ansSnap.data()?['correct'] ?? false) == true)
              : false;

      // 解答の保存/更新
      tx.set(ansRef, {
        'round': roundNo,
        'uid': u,
        'answer': answer,
        'timeMs': timeMs,
        'correct': correct,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 正解 & 未加点ならスコア加算
      if (correct && !alreadyCorrect) {
        final roundTimeSec = (roomSnap.data()?['roundTimeSec'] ?? 20) as int;
        final points = _calcScore(timeMs, roundTimeSec);
        tx.update(playerRef, {'score': FieldValue.increment(points)});
      }
    });
  }

  // ========= 再戦投票 =========

  Future<void> voteRematch(String roomId) async {
    final u = uid ?? '';
    await _db.collection('rooms').doc(roomId).collection('rematch').doc(u).set({
      'uid': u,
      'ready': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ========= 互換API（古い画面が呼んでいても落ちないように） =========

  /// 旧API互換：誰か正解 or 全員回答なら次へ/終了へ
  Future<void> tryFinishRoundOnFirstCorrect(
    String roomId, [
    int? roundMaybe,
    int? totalMaybe,
  ]) async {
    final room = _db.collection('rooms').doc(roomId);
    final roomSnap = await room.get();
    final data = roomSnap.data();
    if (data == null) return;

    final curRound = roundMaybe ?? (data['round'] ?? 0) as int;
    final total = totalMaybe ?? ((data['questions'] ?? []) as List).length;

    final players = await room.collection('players').get();
    final answers =
        await room
            .collection('answers')
            .where('round', isEqualTo: curRound)
            .get();

    final anyCorrect = answers.docs.any(
      (d) => (d.data()['correct'] ?? false) == true,
    );
    final allAnswered =
        players.docs.isNotEmpty && answers.docs.length >= players.docs.length;

    if (anyCorrect || allAnswered) {
      if (curRound < total - 1) {
        await nextRound(roomId, curRound + 1);
      } else {
        await finishMatch(roomId);
      }
    }
  }

  // ========= 内部ユーティリティ =========

  Future<void> _joinRoom(String roomId) async {
    final u = user;
    if (u == null) return;
    final ref = _db.collection('rooms').doc(roomId);

    await ref.set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ref.collection('players').doc(u.uid).set({
      'uid': u.uid,
      'displayName': u.displayName ?? 'Player',
      'photoURL': u.photoURL,
      'score': 0,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> _createRoomDoc({
    required bool isPrivate,
    required String difficulty,
  }) async {
    final u = user!;
    final doc = _db.collection('rooms').doc();
    final code = isPrivate ? await _genUniqueCode() : null;

    await doc.set({
      'hostUid': u.uid,
      'status': 'waiting',
      'difficulty': difficulty,
      'round': 0,
      'roundTimeSec': 20,
      'isPrivate': isPrivate,
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<String> _genUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 0/O,1/I除外
    final rnd = Random.secure();
    while (true) {
      final c =
          List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
      final hit =
          await _db
              .collection('rooms')
              .where('code', isEqualTo: c)
              .limit(1)
              .get();
      if (hit.docs.isEmpty) return c;
    }
  }

  Future<void> _clearSubcollection(CollectionReference col) async {
    final snap = await col.get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  /// 経過時間に応じたスコア（100〜1000）
  int _calcScore(int timeMs, int roundTimeSec) {
    final maxMs = max(1, roundTimeSec * 1000);
    final remain = (maxMs - timeMs).clamp(0, maxMs);
    final ratio = remain / maxMs; // 0.0〜1.0
    return 100 + (900 * ratio).round();
  }
}
