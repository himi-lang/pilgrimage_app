// lib/versus/versus_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VersusService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  // 6桁コード（公開ルーム用じゃないが、既存仕様を踏襲）
  String _code6() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // -------------------
  // ルーム作成 / 参加系
  // -------------------
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
      'difficulty': difficulty, // ← easy/normal/hard
      'round': 0,
      'roundTimeSec': 20,
      'questions': [],
      'roundStartedAt': null,
      'firstCorrect': null, // ← 追加：毎ラウンド最初の正解者情報
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

  // -------------------
  // ゲーム進行
  // -------------------

  /// 開始：ホストのみ。問題配列は毎回シャッフル（完全ランダム）
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
        throw StateError('host-only');
      }

      // 完全ランダム（配列順を毎回シャッフル）
      final rnd = Random.secure();
      final qs = List<Map<String, dynamic>>.from(questions)..shuffle(rnd);

      tx.update(roomRef, {
        'questions': qs,
        'status': 'playing',
        'round': 0,
        'roundStartedAt': FieldValue.serverTimestamp(),
        'firstCorrect': null, // ラウンド開始でクリア
      });
    });
  }

  /// 次ラウンド：ホストのみ。開始時刻を更新し、firstCorrect をリセット
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
        'firstCorrect': null,
      });
    });
  }

  /// 回答送信（冪等化）：同ラウンドに自分の解答Docがあればスコア加算しない
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
        .doc('${roundNo}_${uid.substring(0, 8)}'); // ← 既存命名を維持

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

  /// 誰かが最初に正解したらラウンドを確定して即次へ
  /// （UI側で正解送信後に呼ぶ）
  Future<void> tryFinishRoundOnFirstCorrect({
    required String roomId,
    required int roundNo,
    required String correctAnswer,
  }) async {
    final roomRef = _db.collection('rooms').doc(roomId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;

      final currentRound = (data['round'] ?? 0) as int;
      if (currentRound != roundNo) return; // 既に進んでいる

      final first = data['firstCorrect'] as Map<String, dynamic>?;
      if (first != null && (first['round'] ?? -1) == roundNo) {
        // すでに最初の正解が登録済み
        return;
      }

      // 最初の正解者を確定し、答えを公開
      tx.update(roomRef, {
        'firstCorrect': {
          'round': roundNo,
          'answer': correctAnswer,
          'by': _uid,
          'at': FieldValue.serverTimestamp(),
        },
      });

      // 次のラウンドへ
      tx.update(roomRef, {
        'round': roundNo + 1,
        'roundStartedAt': FieldValue.serverTimestamp(),
        'firstCorrect': null, // 直後に UI が次を描画する前提で一応クリアしておくならコメントアウト
      });
    });
  }

  /// 退出：最古参へホスト移譲 or 参加者0なら部屋削除（トランザクション）
  Future<void> leaveRoom(String roomId) async {
    final uid = _auth.currentUser!.uid;
    final roomRef = _db.collection('rooms').doc(roomId);
    final playerRef = roomRef.collection('players').doc(uid);

    await _db.runTransaction((tx) async {
      // 自分を消す
      tx.delete(playerRef);

      final roomSnap = await tx.get(roomRef);
      final hostUid = (roomSnap.data()?['hostUid'] as String?);

      // 残存プレイヤーを1人取得（joinedAt 昇順）
      final rest =
          await roomRef
              .collection('players')
              .orderBy('joinedAt')
              .limit(1)
              .get();

      if (rest.docs.isEmpty) {
        tx.delete(roomRef);
        return;
      }

      // ホストが抜けたら移譲
      if (hostUid == uid) {
        tx.update(roomRef, {'hostUid': rest.docs.first.id});
      }
    });
  }
}
