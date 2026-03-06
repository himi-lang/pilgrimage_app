import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class VersusService {
  static const int publicMaxPlayers = 5;
  static const int privateMaxPlayers = 2;
  static const Duration stalePresenceTtl = Duration(seconds: 45);
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;
  User? get user => _auth.currentUser;

  // ========= ロビー系 =========

  /// クイックマッチ。待機中の公開ルームに入る。無ければ作る。
  Future<String> quickJoin() async {
    final me = uid;
    if (me == null) {
      throw StateError('Not signed in');
    }

    // 同時参加レース対策:
    // 1) 探す 2) 少し待ってもう一度探す 3) それでも無ければ作る
    for (var attempt = 0; attempt < 4; attempt++) {
      final found = await _findOpenPublicRoom(excludeHostUid: me);
      if (found != null) {
        final joined = await _tryJoinPublicRoom(found);
        if (joined) return found;
      }

      await Future<void>.delayed(
        Duration(milliseconds: 250 + Random().nextInt(550)),
      );

      final foundAfterWait = await _findOpenPublicRoom(excludeHostUid: me);
      if (foundAfterWait != null) {
        final joined = await _tryJoinPublicRoom(foundAfterWait);
        if (joined) return foundAfterWait;
      }
    }

    final roomId = await _createRoomDoc(isPrivate: false);
    await _joinRoom(roomId);

    // 同時作成で分断した場合、他の公開待機ルームへ寄せる
    final candidate = await _findOpenPublicRoom(excludeHostUid: me);
    if (candidate != null && candidate != roomId) {
      final joined = await _tryJoinPublicRoom(candidate);
      if (joined) {
        await leaveRoom(roomId);
        return candidate;
      }
    }
    return roomId;
  }

  /// ルームを新規作成（プライベート/公開）
  Future<String> createRoom({required bool isPrivate}) async {
    final id = await _createRoomDoc(isPrivate: isPrivate);
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
    try {
      await pruneStalePlayers(id);
      await _joinRoom(id, enforceCapacity: true);
      return id;
    } on StateError {
      return null;
    }
  }

  /// ルームから退出
  Future<void> leaveRoom(String roomId) async {
    final u = uid;
    if (u == null) return;
    final roomRef = _db.collection('rooms').doc(roomId);
    final playerRef = roomRef.collection('players').doc(u);
    final rematchRef = roomRef.collection('rematch').doc(u);
    await _db.runTransaction((tx) async {
      final roomSnap = await tx.get(roomRef);
      if (!roomSnap.exists) return;
      final playerSnap = await tx.get(playerRef);
      if (!playerSnap.exists) return;

      final data = roomSnap.data() ?? <String, dynamic>{};
      final count = (data['playerCount'] ?? 0) as int;
      final newCount = max(0, count - 1);

      tx.delete(playerRef);
      tx.delete(rematchRef);

      if (newCount == 0) {
        tx.delete(roomRef);
        return;
      }

      final patch = <String, dynamic>{
        'playerCount': newCount,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.update(roomRef, patch);
    });
  }

  Future<void> touchPresence(String roomId) async {
    final u = uid;
    if (u == null) return;
    try {
      await _db
          .collection('rooms')
          .doc(roomId)
          .collection('players')
          .doc(u)
          .update({'lastActiveAt': FieldValue.serverTimestamp()});
    } catch (_) {
      // no-op
    }
  }

  Future<void> pruneStalePlayers(
    String roomId, {
    Duration staleAfter = stalePresenceTtl,
  }) async {
    final roomRef = _db.collection('rooms').doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) return;

    final cutoff = Timestamp.fromDate(DateTime.now().subtract(staleAfter));
    final playersRef = roomRef.collection('players');

    final staleByHeartbeat =
        await playersRef.where('lastActiveAt', isLessThan: cutoff).get();
    final staleWithoutHeartbeat =
        await playersRef.where('lastActiveAt', isEqualTo: null).get();

    final stale = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in staleByHeartbeat.docs) {
      stale[d.id] = d;
    }
    for (final d in staleWithoutHeartbeat.docs) {
      final joinedAt = d.data()['joinedAt'] as Timestamp?;
      final joinedAtMs = joinedAt?.millisecondsSinceEpoch;
      final cutoffMs = cutoff.millisecondsSinceEpoch;
      if (joinedAtMs != null && joinedAtMs <= cutoffMs) {
        stale[d.id] = d;
      }
    }
    if (stale.isEmpty) return;

    final batch = _db.batch();
    for (final d in stale.values) {
      batch.delete(d.reference);
      batch.delete(roomRef.collection('rematch').doc(d.id));
    }
    await batch.commit();

    final remainingSnap = await playersRef.get();
    final remainingDocs = remainingSnap.docs.toList();
    if (remainingDocs.isEmpty) {
      await roomRef.delete();
      return;
    }

    final roomData = roomSnap.data() ?? <String, dynamic>{};
    final hostUid = (roomData['hostUid'] ?? '').toString();
    final removedHost = hostUid.isNotEmpty && stale.containsKey(hostUid);

    final patch = <String, dynamic>{
      'playerCount': remainingDocs.length,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (removedHost) {
      remainingDocs.sort((a, b) {
        final ta =
            (a.data()['joinedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb =
            (b.data()['joinedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return ta.compareTo(tb);
      });
      final nextHost =
          (remainingDocs.first.data()['uid'] ?? remainingDocs.first.id)
              .toString();
      patch['hostUid'] = nextHost;
    }

    await roomRef.update(patch);
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
      'startingBy': FieldValue.delete(),
      'startLockAt': FieldValue.delete(),
      'publicCountdownStartedAt': FieldValue.delete(),
    });
  }

  Future<bool> tryAcquireStartLock(String roomId) async {
    final u = uid;
    if (u == null) return false;
    final roomRef = _db.collection('rooms').doc(roomId);
    var acquired = false;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      final status = (data['status'] ?? 'waiting').toString();
      if (status != 'waiting') return;

      final startingBy = (data['startingBy'] ?? '').toString();
      if (startingBy.isNotEmpty && startingBy != u) return;

      tx.update(roomRef, {
        'startingBy': u,
        'startLockAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      acquired = true;
    });
    return acquired;
  }

  Future<void> releaseStartLock(String roomId) async {
    await _db.collection('rooms').doc(roomId).update({
      'startingBy': FieldValue.delete(),
      'startLockAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
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

  Future<void> _joinRoom(String roomId, {bool enforceCapacity = false}) async {
    final u = user;
    if (u == null) return;
    final ref = _db.collection('rooms').doc(roomId);
    final playerRef = ref.collection('players').doc(u.uid);

    await _db.runTransaction((tx) async {
      final roomSnap = await tx.get(ref);
      if (!roomSnap.exists) {
        throw StateError('room-not-found');
      }
      final playerSnap = await tx.get(playerRef);
      final data = roomSnap.data() ?? <String, dynamic>{};
      final status = (data['status'] ?? 'waiting').toString();
      final playerCount = (data['playerCount'] ?? 0) as int;
      final isPrivate = (data['isPrivate'] ?? true) as bool;
      final alreadyJoined = playerSnap.exists;
      final capacity = isPrivate ? privateMaxPlayers : publicMaxPlayers;

      if (enforceCapacity && !alreadyJoined && status != 'waiting') {
        throw StateError('room-closed');
      }
      if (enforceCapacity && !alreadyJoined && playerCount >= capacity) {
        throw StateError('room-full');
      }

      tx.set(playerRef, {
        'uid': u.uid,
        'displayName': u.displayName ?? 'Player',
        'photoURL': u.photoURL,
        'score': playerSnap.exists ? (playerSnap.data()?['score'] ?? 0) : 0,
        'startReady': false,
        'lastActiveAt': FieldValue.serverTimestamp(),
        'joinedAt':
            playerSnap.exists
                ? (playerSnap.data()?['joinedAt'] ??
                    FieldValue.serverTimestamp())
                : FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final newCount = alreadyJoined ? playerCount : (playerCount + 1);
      final patch = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'playerCount': newCount,
      };
      tx.update(ref, patch);
    });
  }

  Future<String> _createRoomDoc({required bool isPrivate}) async {
    final u = user!;
    final doc = _db.collection('rooms').doc();
    final code = isPrivate ? await _genUniqueCode() : null;

    await doc.set({
      'hostUid': u.uid,
      'status': 'waiting',
      'round': 0,
      'roundTimeSec': 20,
      'playerCount': 0,
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

  Future<String?> _findOpenPublicRoom({required String excludeHostUid}) async {
    String? pickBest(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      final candidates =
          docs.where((d) {
            final data = d.data();
            final isPrivate = (data['isPrivate'] ?? true) as bool;
            final hostUid = (data['hostUid'] ?? '').toString();
            final playerCount = (data['playerCount'] ?? 0) as int;
            return !isPrivate &&
                hostUid != excludeHostUid &&
                playerCount < publicMaxPlayers;
          }).toList();
      if (candidates.isEmpty) return null;

      candidates.sort((a, b) {
        final da = a.data();
        final db = b.data();
        final pa = (da['playerCount'] ?? 0) as int;
        final pb = (db['playerCount'] ?? 0) as int;
        if (pa != pb) return pb.compareTo(pa); // 先に埋まりかけを優先

        final ta = (da['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb = (db['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return ta.compareTo(tb);
      });
      return candidates.first.id;
    }

    try {
      final qs =
          await _db
              .collection('rooms')
              .where('isPrivate', isEqualTo: false)
              .where('status', isEqualTo: 'waiting')
              .limit(20)
              .get();
      final best = pickBest(qs.docs);
      if (best != null) return best;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VersusService] optimized quickJoin query failed: $e');
      }
    }

    // フォールバック: インデックス未作成時でも動くように最小条件で取得してクライアント側で絞る
    try {
      final qs =
          await _db
              .collection('rooms')
              .where('status', isEqualTo: 'waiting')
              .limit(30)
              .get();
      final best = pickBest(qs.docs);
      if (best != null) return best;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VersusService] fallback quickJoin query failed: $e');
      }
    }

    return null;
  }

  Future<bool> _tryJoinPublicRoom(String roomId) async {
    try {
      await pruneStalePlayers(roomId);
      await _joinRoom(roomId, enforceCapacity: true);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VersusService] join candidate failed: $roomId, error=$e');
      }
      return false;
    }
  }
}
