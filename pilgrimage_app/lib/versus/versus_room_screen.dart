import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../widgets/app_ui.dart';
import '../service/spot_image.dart';
import '../mode_selection_screen.dart';
import 'versus_service.dart';

// ===== 設定 =====
const bool _MUTE_SNACK = true; // 画面下ログを抑制（true推奨）
const int _REVEAL_HOLD_MS = 3000; // 正解公開→次問題までの待機(ms)
const int _REMATCH_WINDOW_SEC = 10; // リザルトでの再戦投票受付(秒)

class VersusRoomScreen extends StatefulWidget {
  final String roomId;
  const VersusRoomScreen({super.key, required this.roomId});
  @override
  State<VersusRoomScreen> createState() => _VersusRoomScreenState();
}

class _VersusRoomScreenState extends State<VersusRoomScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _svc = VersusService();

  bool get isHost => _hostUid == _auth.currentUser?.uid;
  String? _hostUid;
  bool _startingInProgress = false;

  // 自動進行監視
  StreamSubscription? _autoAnsSub;
  StreamSubscription? _autoPlayersSub;
  int _playersCount = 0;
  int? _watchingRound;
  bool _advancedThisRound = false;

  // 四択候補のグローバルプール
  List<String> _globalWorkTitlePool = [];

  @override
  void initState() {
    super.initState();
    _loadGlobalWorkPool();
  }

  @override
  void dispose() {
    _autoAnsSub?.cancel();
    _autoPlayersSub?.cancel();
    super.dispose();
  }

  Future<void> _loadGlobalWorkPool() async {
    try {
      final ws = await _db.collection('聖地情報').get();
      setState(() {
        _globalWorkTitlePool =
            ws.docs.map((d) => d.id).whereType<String>().toList();
      });
    } catch (_) {}
  }

  Future<bool> _confirmLeaveRoom(BuildContext context) async {
    final msg =
        isHost ? 'ホストが離脱するとルームが終了する場合があります。退出しますか？' : '対戦を退出します。よろしいですか？';
    final res = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('対戦から離脱'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('離脱する'),
              ),
            ],
          ),
    );
    return res ?? false;
  }

  // ===== 対戦モード選択へ戻る =====
  Future<void> _goLobby() async {
    await _svc.leaveRoom(widget.roomId);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      CupertinoPageRoute(builder: (_) => const VersusModeMenuScreen()),
      (_) => false,
    );
  }

  // ===== スコア/解答のクリア（再戦開始時に使用） =====
  Future<void> _resetPlayersScore() async {
    final snap =
        await _db
            .collection('rooms')
            .doc(widget.roomId)
            .collection('players')
            .get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'score': 0});
    }
    await batch.commit();
  }

  Future<void> _clearAnswers() async {
    final ref = _db
        .collection('rooms')
        .doc(widget.roomId)
        .collection('answers');
    final snap = await ref.get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ===== 開始ボタン =====
  Future<void> _handleStart(Map<String, dynamic> data) async {
    if (_startingInProgress) return;
    _startingInProgress = true;
    try {
      final locked = await _svc.tryAcquireStartLock(widget.roomId);
      if (!locked) return;
      if (!mounted) return;
      if (!_MUTE_SNACK) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('問題を読み込み中…')));
      }
      final qs = await _buildQuestions(
        count: 5,
      );
      if (qs.isEmpty) {
        await _svc.releaseStartLock(widget.roomId);
        if (!mounted) return;
        if (!_MUTE_SNACK) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('問題データが見つかりません（聖地情報コレクションを確認してください）')),
          );
        }
        return;
      }
      await _svc.startMatch(widget.roomId, qs);
      if (!_MUTE_SNACK && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('対戦を開始しました')));
      }
    } catch (e) {
      await _svc.releaseStartLock(widget.roomId);
      if (!_MUTE_SNACK && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('開始に失敗: $e')));
      }
    } finally {
      _startingInProgress = false;
    }
  }

  // ===== 自動で次へ（誰か正解 or 全員回答） =====
  void _ensureAutoAdvance(String roomId, int round, int total) {
    if (!isHost) return;
    if (_watchingRound == round) return;

    _autoAnsSub?.cancel();
    _autoPlayersSub?.cancel();
    _advancedThisRound = false;
    _watchingRound = round;

    final roomDoc = _db.collection('rooms').doc(roomId);

    _autoPlayersSub = roomDoc.collection('players').snapshots().listen((s) {
      _playersCount = s.docs.length;
    });

    _autoAnsSub = roomDoc
        .collection('answers')
        .where('round', isEqualTo: round)
        .snapshots()
        .listen((s) async {
          if (_advancedThisRound) return;
          final docs = s.docs;
          final allAnswered =
              (_playersCount > 0) && (docs.length >= _playersCount);

          if (allAnswered) {
            _advancedThisRound = true;
            await Future.delayed(const Duration(milliseconds: _REVEAL_HOLD_MS));
            final snap = await roomDoc.get();
            final data = snap.data();
            if (data == null) return;
            final cur = (data['round'] ?? 0) as int;
            if (cur != round) return;
            final qs = (data['questions'] ?? []) as List;
            if (cur < qs.length - 1) {
              await _svc.nextRound(roomId, cur + 1);
            } else {
              await _svc.finishMatch(roomId); // finishedAt を刻む
            }
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final roomRef = _db.collection('rooms').doc(widget.roomId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roomRef.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const CupertinoPageScaffold(
            child: Material(
              color: Colors.transparent,
              child: Center(child: CupertinoActivityIndicator()),
            ),
          );
        }
        final data = snap.data!.data();
        if (data == null) {
          return const CupertinoPageScaffold(
            child: Material(
              color: Colors.transparent,
              child: Center(child: Text('部屋が削除されました')),
            ),
          );
        }
        _hostUid = data['hostUid'] as String?;
        final status = (data['status'] as String?) ?? 'waiting';
        final round = (data['round'] ?? 0) as int;
        final List qs = (data['questions'] ?? []) as List;
        final int roundTimeSec = (data['roundTimeSec'] ?? 20) as int;
        final DateTime? roundStartedAt =
            (data['roundStartedAt'] as Timestamp?)?.toDate();
        final DateTime? finishedAt =
            (data['finishedAt'] as Timestamp?)?.toDate();
        final hasCode =
            (data['code'] as String?)?.isNotEmpty == true; // プライベート判定

        final localPool =
            qs
                .map((e) => (e as Map)['workTitle'])
                .whereType<String>()
                .toSet()
                .toList();
        final workPool =
            _globalWorkTitlePool.isNotEmpty ? _globalWorkTitlePool : localPool;

        if (status != 'waiting' && qs.isNotEmpty) {
          _ensureAutoAdvance(widget.roomId, round, qs.length);
        }

        return WillPopScope(
          onWillPop: () async {
            final ok = await _confirmLeaveRoom(context);
            if (ok) await _svc.leaveRoom(widget.roomId);
            return ok;
          },
          child: CupertinoPageScaffold(
            navigationBar: commonAppBar(
              context,
              title: '対戦ルーム',
              currentMode: AppMode.versus,
              actionsExtra: [
                if (hasCode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: Text(
                        '招待: ${data['code']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 30,
                  onPressed: () async {
                    final ok = await _confirmLeaveRoom(context);
                    if (ok) await _goLobby();
                  },
                  child: const Icon(CupertinoIcons.home),
                ),
              ],
              modeConfirm: () => _confirmLeaveRoom(context),
              modeBeforeNavigate: () => _svc.leaveRoom(widget.roomId),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                _PlayersList(roomId: widget.roomId),
                const Divider(height: 1),
                Expanded(
                  child: () {
                    if (status == 'waiting') {
                      if (hasCode) {
                        return _WaitingPane(
                          isHost: isHost,
                          onStart: () => _handleStart(data),
                        );
                      }
                      return _PublicWaitingPane(
                        roomId: widget.roomId,
                        onStart: () => _handleStart(data),
                      );
                    }
                    if (status == 'finished' ||
                        qs.isEmpty ||
                        round < 0 ||
                        round >= qs.length) {
                      return _FinishedPane(
                        roomId: widget.roomId,
                        finishedAt: finishedAt,
                        isPrivate: hasCode,
                        isHost: isHost,
                        onRematchStartByHost: (
                          countHint,
                        ) async {
                          final qsNew = await _buildQuestions(
                            count: countHint ?? (qs.isNotEmpty ? qs.length : 5),
                          );
                          await _resetPlayersScore();
                          await _clearAnswers();
                          await _svc.startMatch(widget.roomId, qsNew);
                        },
                        onGoLobby: _goLobby,
                      );
                    }
                    return _PlayPane(
                      roomId: widget.roomId,
                      question: Map<String, dynamic>.from(qs[round] as Map),
                      round: round,
                      total: qs.length,
                      roundTimeSec: roundTimeSec,
                      roundStartedAt: roundStartedAt,
                      workPool: workPool,
                      onSubmit: (ans, timeMs, {bool timeUp = false}) async {
                        final target = (qs[round]['workTitle'] ?? '') as String;
                        final correct = _match(ans, target);

                        await _svc.submitAnswer(
                          roomId: widget.roomId,
                          roundNo: round,
                          answer: ans,
                          timeMs: timeMs,
                          correct: correct,
                        );

                        if (isHost && (timeUp || correct)) {
                          await Future.delayed(
                            const Duration(milliseconds: _REVEAL_HOLD_MS),
                          );
                          final roomDoc = _db
                              .collection('rooms')
                              .doc(widget.roomId);
                          final dataNow = (await roomDoc.get()).data();
                          if (dataNow == null) return;
                          final cur = (dataNow['round'] ?? 0) as int;
                          final total =
                              ((dataNow['questions'] ?? []) as List).length;
                          if (cur < total - 1) {
                            await _svc.nextRound(widget.roomId, cur + 1);
                          } else {
                            await _svc.finishMatch(widget.roomId);
                          }
                        }
                      },
                    );
                  }(),
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===== 問題生成（作品重複なし） =====
  Future<List<Map<String, dynamic>>> _buildQuestions(
    {
    int count = 5,
  }) async {
    final rand = Random();
    final worksSnap = await _db.collection('聖地情報').get();
    final works = worksSnap.docs.toList()..shuffle(rand);

    final out = <Map<String, dynamic>>[];
    final usedWorks = <String>{};

    for (final w in works) {
      if (usedWorks.contains(w.id)) continue;
      final spotsSnap =
          await _db.collection('聖地情報').doc(w.id).collection('聖地').get();
      if (spotsSnap.docs.isEmpty) continue;

      final d = (spotsSnap.docs.toList()..shuffle(rand)).first;
      final m = d.data();
      double _to(x) => (x is num) ? x.toDouble() : double.tryParse('$x') ?? 0.0;

      out.add({
        'id': d.id,
        'name': m['name'] ?? '',
        'workTitle': (m['workTitle'] ?? w.id) as String,
        'image': m['image'] ?? '',
        'address': (m['address'] ?? '').toString(),
        'latitude': _to(m['latitude']),
        'longitude': _to(m['longitude']),
      });
      usedWorks.add(w.id);
      if (out.length >= count) break;
    }

    out.shuffle(rand);
    return out;
  }

  bool _match(String ans, String workTitle) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s　]'), '');
    return norm(ans) == norm(workTitle);
  }
}

// ===== プレイヤー一覧 =====
class _PlayersList extends StatelessWidget {
  final String roomId;
  const _PlayersList({required this.roomId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomId)
        .collection('players');
    return SizedBox(
      height: 110,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ref.orderBy('joinedAt').snapshots(),
        builder: (c, s) {
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final photo = d['photoURL'] as String?;
              return Column(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage:
                        (photo != null && photo.isNotEmpty)
                            ? NetworkImage(photo)
                            : null,
                    child:
                        (photo == null || photo.isEmpty)
                            ? const Icon(Icons.person)
                            : null,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 96,
                    child: Text(
                      (d['displayName'] ?? 'Player'),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      'Score ${d['score'] ?? 0}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ===== 待機画面 =====
class _WaitingPane extends StatelessWidget {
  final bool isHost;
  final VoidCallback onStart;
  const _WaitingPane({required this.isHost, required this.onStart});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('参加者を待っています…'),
          const SizedBox(height: 12),
          if (isHost)
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('開始'),
            ),
        ],
      ),
    );
  }
}

class _PublicWaitingPane extends StatefulWidget {
  final String roomId;
  final Future<void> Function() onStart;
  const _PublicWaitingPane({required this.roomId, required this.onStart});

  @override
  State<_PublicWaitingPane> createState() => _PublicWaitingPaneState();
}

class _PublicWaitingPaneState extends State<_PublicWaitingPane> {
  static const int _targetPlayers = VersusService.publicMaxPlayers;
  static const int _countdownSec = 30;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Timer? _ticker;
  bool _starting = false;
  bool _syncingCountdown = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _setReady(bool ready) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref =
        _db.collection('rooms').doc(widget.roomId).collection('players').doc(uid);
    await ref.set({'startReady': ready}, SetOptions(merge: true));
  }

  Future<void> _syncCountdown({
    required int playersCount,
    required Timestamp? countdownStartedAt,
  }) async {
    if (_syncingCountdown) return;
    final roomRef = _db.collection('rooms').doc(widget.roomId);
    _syncingCountdown = true;
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(roomRef);
        if (!snap.exists) return;
        final data = snap.data() ?? <String, dynamic>{};
        final status = (data['status'] ?? 'waiting').toString();
        if (status != 'waiting') return;
        final hasCountdown = data['publicCountdownStartedAt'] != null;

        if (playersCount > 0 && !hasCountdown) {
          tx.update(roomRef, {
            'publicCountdownStartedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else if (playersCount == 0 && hasCountdown) {
          tx.update(roomRef, {
            'publicCountdownStartedAt': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else if (playersCount > 0 && countdownStartedAt == null) {
          tx.update(roomRef, {
            'publicCountdownStartedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {
      // noop
    } finally {
      _syncingCountdown = false;
    }
  }

  Future<void> _tryAutoStart({
    required int playersCount,
    required int readyCount,
    required int remainSec,
  }) async {
    if (_starting) return;
    if (playersCount <= 0) return;

    final reachedTarget = playersCount >= _targetPlayers;
    final allReady = playersCount > 0 && readyCount >= playersCount;
    final timeout = remainSec <= 0;
    if (!(reachedTarget || allReady || timeout)) return;

    _starting = true;
    try {
      await widget.onStart();
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid ?? '';
    final roomRef = _db.collection('rooms').doc(widget.roomId);
    final playersRef = roomRef.collection('players');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roomRef.snapshots(),
      builder: (context, roomSnap) {
        final roomData = roomSnap.data?.data() ?? <String, dynamic>{};
        final status = (roomData['status'] ?? 'waiting').toString();
        final countdownTs =
            roomData['publicCountdownStartedAt'] as Timestamp?;
        final elapsed =
            countdownTs == null
                ? 0
                : DateTime.now().difference(countdownTs.toDate()).inSeconds;
        final remainSec = (_countdownSec - elapsed).clamp(0, _countdownSec);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: playersRef.snapshots(),
          builder: (context, playersSnap) {
            final players =
                playersSnap.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final playersCount = players.length;

            if (status == 'waiting') {
              _syncCountdown(
                playersCount: playersCount,
                countdownStartedAt: countdownTs,
              );
            }

            final readyCount =
                players.where((d) => (d.data()['startReady'] ?? false) == true).length;
            final myReady = players.any(
              (d) =>
                  (d.data()['uid'] ?? '').toString() == uid &&
                  (d.data()['startReady'] ?? false) == true,
            );

            if (status == 'waiting') {
              _tryAutoStart(
                playersCount: playersCount,
                readyCount: readyCount,
                remainSec: remainSec,
              );
            }

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('現在の人数: $playersCount / $_targetPlayers'),
                  const SizedBox(height: 8),
                  Text('開始ボタンを押した人数: $readyCount / $playersCount'),
                  const SizedBox(height: 12),
                  CupertinoButton.filled(
                    onPressed: status == 'waiting' ? () => _setReady(!myReady) : null,
                    child: Text(myReady ? '開始を取り消す' : '開始'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'スタートまで: $remainSec 秒',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ===== リザルト（再戦投票 + ロビーへ） =====
class _FinishedPane extends StatefulWidget {
  final String roomId;
  final DateTime? finishedAt;
  final bool isPrivate; // 招待コードあり＝プライベート
  final bool isHost;
  final Future<void> Function(int? countHint)
  onRematchStartByHost;
  final VoidCallback onGoLobby;

  const _FinishedPane({
    required this.roomId,
    required this.finishedAt,
    required this.isPrivate,
    required this.isHost,
    required this.onRematchStartByHost,
    required this.onGoLobby,
  });

  @override
  State<_FinishedPane> createState() => _FinishedPaneState();
}

class _FinishedPaneState extends State<_FinishedPane> {
  int _players = 0;
  int _ready = 0;
  bool _voted = false;
  Timer? _timer;
  int _remain = _REMATCH_WINDOW_SEC;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('players')
        .snapshots()
        .listen((s) => setState(() => _players = s.docs.length));

    FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('rematch')
        .snapshots()
        .listen((s) => setState(() => _ready = s.docs.length));

    final started = widget.finishedAt ?? DateTime.now();
    _remain =
        _REMATCH_WINDOW_SEC - DateTime.now().difference(started).inSeconds;
    if (_remain < 0) _remain = 0;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() => _remain = (_remain - 1).clamp(0, _REMATCH_WINDOW_SEC));

      // 全員押したら（プラベのみ）→ ホストが再戦開始
      if (widget.isPrivate &&
          _ready > 0 &&
          _players > 0 &&
          _ready >= _players) {
        if (widget.isHost) {
          await widget.onRematchStartByHost(null);
        }
      }

      // タイムアップ → ロビーへ
      if (_remain == 0) {
        _timer?.cancel();
        widget.onGoLobby();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _vote() async {
    if (_voted) return;
    await VersusService().voteRematch(widget.roomId);
    setState(() => _voted = true);
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('players')
        .orderBy('score', descending: true);

    return Column(
      children: [
        // 上部操作
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (widget.isPrivate && !_voted) ? _vote : null,
                      icon: const Icon(Icons.replay),
                      label: Text(
                        widget.isPrivate
                            ? (_voted ? '再戦希望済み' : '再戦（全員で押す）')
                            : '対戦モード選択へ戻る',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.isPrivate)
                    Text(
                      '$_ready / $_players 準備',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.timer, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    widget.isPrivate
                        ? '$_remain s 内に全員が押したら再戦開始'
                        : '$_remain s 後に対戦モード選択へ',
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: widget.onGoLobby,
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('対戦モード選択へ'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // スコア一覧
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (c, s) {
              if (!s.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = s.data!.docs;
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  return ListTile(
                    leading: Text('#${i + 1}'),
                    title: Text(d['displayName'] ?? 'Player'),
                    trailing: Text('${d['score'] ?? 0}'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ===== プレイ画面 =====
class _PlayPane extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic> question;
  final int round;
  final int total;
  final int roundTimeSec;
  final DateTime? roundStartedAt;
  final List<String> workPool;
  final Future<void> Function(String ans, int timeMs, {bool timeUp}) onSubmit;

  const _PlayPane({
    required this.roomId,
    required this.question,
    required this.round,
    required this.total,
    required this.roundTimeSec,
    required this.roundStartedAt,
    required this.workPool,
    required this.onSubmit,
  });

  @override
  State<_PlayPane> createState() => _PlayPaneState();
}

class _PlayPaneState extends State<_PlayPane> {
  late Stopwatch _sw;
  bool _submitted = false;
  bool _roundClosed = false;
  late int _remain;
  Timer? _ticker;

  final List<String> _choices = [];
  int? _correctIndex;
  int? _pickedIndex;
  bool _pause = false;

  String? _revealTitle;
  String? _resultText;

  StreamSubscription? _answersSub;
  int _playersCount = 0;
  int _answersCount = 0;

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
    _listenPlayersCount();
    _setupForRound();
    _listenAnswers();
  }

  @override
  void didUpdateWidget(covariant _PlayPane old) {
    super.didUpdateWidget(old);
    if (widget.round != old.round) {
      _submitted = false;
      _roundClosed = false;
      _revealTitle = null;
      _resultText = null;
      _sw
        ..reset()
        ..start();
      _setupForRound();
      _listenAnswers();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _answersSub?.cancel();
    super.dispose();
  }

  void _listenPlayersCount() async {
    final s =
        await FirebaseFirestore.instance
            .collection('rooms')
            .doc(widget.roomId)
            .collection('players')
            .get();
    _playersCount = s.docs.length;
  }

  void _listenAnswers() {
    _answersSub?.cancel();
    _answersSub = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('answers')
        .where('round', isEqualTo: widget.round)
        .snapshots()
        .listen((s) {
          _answersCount = s.docs.length;
          final allAnswered =
              (_playersCount > 0) && (_answersCount >= _playersCount);

          if (allAnswered) {
            final title = (widget.question['workTitle'] ?? '') as String;
            setState(() {
              _roundClosed = true;
              _revealTitle = title;
            });
          }
        });
  }

  void _setupForRound() {
    _setupTimer();
    _prepareChoices();
  }

  void _setupTimer() {
    _ticker?.cancel();
    final start = widget.roundStartedAt ?? DateTime.now();
    _remain = widget.roundTimeSec - DateTime.now().difference(start).inSeconds;
    if (_remain < 0) _remain = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_pause) return;
      setState(() => _remain = (_remain - 1).clamp(0, widget.roundTimeSec));
      if (_remain == 0) {
        _revealTitle ??= (widget.question['workTitle'] ?? '') as String;
        _roundClosed = true;
        _ticker?.cancel();
        if (!_submitted) _submit(timeUp: true);
      }
    });
  }

  void _prepareChoices() {
    final correct = (widget.question['workTitle'] ?? '') as String;
    final qid =
        (widget.question['id'] ?? '${widget.question['name']}') as String;
    final rnd = Random(qid.hashCode);
    final set = <String>{correct};
    final pool = widget.workPool.isNotEmpty ? widget.workPool : [correct];

    while (set.length < 4 && pool.isNotEmpty) {
      final cand = pool[rnd.nextInt(pool.length)];
      if (cand != correct) set.add(cand);
    }
    while (set.length < 4) set.add('（ダミー）${set.length}');
    final list = set.toList()..shuffle(rnd);

    setState(() {
      _choices
        ..clear()
        ..addAll(list);
      _correctIndex = _choices.indexOf(correct);
      _pickedIndex = null;
      _pause = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    double _toD(x) => (x is num) ? x.toDouble() : double.tryParse('$x') ?? 0.0;
    final pos = LatLng(_toD(q['latitude']), _toD(q['longitude']));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          '第${widget.round + 1}問 / ${widget.total}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: _remain / widget.roundTimeSec),
        Row(
          children: [
            Text('残り $_remain s'),
          ],
        ),
        const SizedBox(height: 8),
        if ((q['image'] as String?)?.isNotEmpty == true)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              child: SpotImage(
                raw: (q['image'] ?? '').toString(),
                width: 720,
                cacheWidth: 720,
                fit: BoxFit.cover,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'スポット: ${q['name'] ?? ''}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GoogleMap(
              key: ValueKey('round_map_${widget.round}'),
              initialCameraPosition: CameraPosition(target: pos, zoom: 14),
              markers: {
                Marker(markerId: MarkerId('m_${widget.round}'), position: pos),
              },
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              liteModeEnabled: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildChoicesArea(),
        if (_resultText != null) ...[
          const SizedBox(height: 8),
          Text(
            _resultText!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _resultText!.contains('正解') ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        if (_revealTitle != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '正解：$_revealTitle',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );
  }

  Widget _buildChoicesArea() {
    if (_choices.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 3.2,
      children: List.generate(_choices.length, (i) {
        final picked = _pickedIndex == i;
        final isCorrect = (_correctIndex == i);
        Color? bg;
        if (_pickedIndex != null) {
          bg = isCorrect ? Colors.green : (picked ? Colors.red : null);
        }
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed:
              (_submitted || _pickedIndex != null || _roundClosed)
                  ? null
                  : () => _onPick(i),
          child: Text(
            _choices[i],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
    );
  }

  Future<void> _onPick(int index) async {
    if (_submitted || _pickedIndex != null || _roundClosed) return;
    setState(() {
      _pause = true;
      _pickedIndex = index;
    });
    final isCorrect = (index == _correctIndex);
    _resultText = isCorrect ? '正解！' : '不正解…';
    await _submit(ans: _choices[index]);
    if (mounted) setState(() => _pause = false);
  }

  Future<void> _submit({String? ans, bool timeUp = false}) async {
    if (_roundClosed && !timeUp) return;
    if (_submitted && !timeUp) return;
    if (!timeUp) _submitted = true;
    _sw.stop();
    final send = ans ?? '';
    await widget.onSubmit(send, _sw.elapsedMilliseconds, timeUp: timeUp);
    if (!mounted) return;
    if (!_MUTE_SNACK && !timeUp) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回答を送信しました')));
    }
    setState(() {});
  }
}
