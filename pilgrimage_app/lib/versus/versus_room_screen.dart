import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

import '../app_routes.dart';
import '../widgets/app_ui.dart';
import '../service/spot_image.dart';
import 'versus_service.dart';

// ===== 設定 =====
const bool _MUTE_SNACK = true; // 画面下ログを抑制（true推奨）
const int _REVEAL_HOLD_MS = 3000; // 正解公開→次問題までの待機(ms)
const int _REMATCH_WINDOW_SEC = 10; // リザルトでの再戦投票受付(秒)

String _trimmedText(dynamic value) => (value ?? '').toString().trim();

String _normalizeWorkTitle(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s　]+'), '');

String _resolveWorkTitle(dynamic value, {required String fallback}) {
  final title = _trimmedText(value);
  if (title.isNotEmpty) return title;
  return _trimmedText(fallback);
}

bool _sameWorkTitle(String left, String right) =>
    _normalizeWorkTitle(left) == _normalizeWorkTitle(right);

String _questionWorkTitle(Map<String, dynamic> question) => _resolveWorkTitle(
  question['workTitle'],
  fallback: _trimmedText(question['workKey']),
);

String _questionSignature(Map<String, dynamic> question) {
  final id = _trimmedText(question['id']);
  final name = _trimmedText(question['name']);
  final workTitle = _questionWorkTitle(question);
  return '$id|$name|$workTitle';
}

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
  String? _roomStatus;
  bool _startingInProgress = false;
  bool _roomDeletedRedirectScheduled = false;
  Timer? _roomDeletedDebounce;

  // 自動進行監視
  StreamSubscription? _autoAnsSub;
  StreamSubscription? _autoPlayersSub;
  Timer? _presenceTimer;
  bool _presenceSyncing = false;
  int _playersCount = 0;
  int? _watchingRound;
  bool _advancedThisRound = false;

  // 四択候補のグローバルプール
  List<String> _globalWorkTitlePool = [];

  @override
  void initState() {
    super.initState();
    _loadGlobalWorkPool();
    _startPresenceHeartbeat();
  }

  @override
  void dispose() {
    _stopAutoAdvanceWatchers();
    _presenceTimer?.cancel();
    _roomDeletedDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadGlobalWorkPool() async {
    try {
      final ws = await _db.collection('聖地情報').get();
      setState(() {
        _globalWorkTitlePool =
            ws.docs
                .map((d) => _resolveWorkTitle(d.id, fallback: ''))
                .where((title) => title.isNotEmpty)
                .toList();
      });
    } catch (_) {}
  }

  void _stopAutoAdvanceWatchers() {
    _autoAnsSub?.cancel();
    _autoAnsSub = null;
    _autoPlayersSub?.cancel();
    _autoPlayersSub = null;
    _playersCount = 0;
    _watchingRound = null;
    _advancedThisRound = false;
  }

  void _startPresenceHeartbeat() {
    _syncPresence();
    _presenceTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _syncPresence();
    });
  }

  Future<void> _syncPresence() async {
    if (_presenceSyncing) return;
    _presenceSyncing = true;
    try {
      await _svc.touchPresence(widget.roomId);
      // 対戦中のprune は一時的なハートビート遅延で進行を壊すため、
      // waiting 中かつホストのみが実行する。
      if (isHost && _roomStatus == 'waiting') {
        await _svc.pruneStalePlayers(widget.roomId);
      }
    } catch (_) {
      // no-op
    } finally {
      _presenceSyncing = false;
    }
  }

  // 一時的なスナップショット欠落で誤って戻さないよう、
  // 2秒継続してルームが消えている場合のみ遷移する。
  void _redirectToModeSelectionOnRoomDeleted() {
    if (_roomDeletedRedirectScheduled || !mounted) return;
    _roomDeletedDebounce ??= Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _roomDeletedRedirectScheduled = true;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.modeSelection, (route) => false);
    });
  }

  void _cancelRoomDeletedRedirect() {
    _roomDeletedDebounce?.cancel();
    _roomDeletedDebounce = null;
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
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.modeSelection, (_) => false);
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
      final qs = await _buildQuestions(count: 5);
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

  Future<void> _advanceToNextRoundOrFinish({
    required DocumentReference<Map<String, dynamic>> roomDoc,
    required int expectedRound,
  }) async {
    final dataNow = (await roomDoc.get()).data();
    if (dataNow == null) return;

    final cur = (dataNow['round'] ?? 0) as int;
    if (cur != expectedRound) return;

    final total = ((dataNow['questions'] ?? []) as List).length;
    if (cur < total - 1) {
      await _svc.nextRound(widget.roomId, cur + 1);
    } else {
      await _svc.finishMatch(widget.roomId);
    }
  }

  // ===== 自動で次へ（誰か正解 or 全員回答） =====
  void _ensureAutoAdvance(String roomId, int round) {
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
            await _advanceToNextRoundOrFinish(
              roomDoc: roomDoc,
              expectedRound: round,
            );
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
          _redirectToModeSelectionOnRoomDeleted();
          return const CupertinoPageScaffold(
            child: Material(
              color: Colors.transparent,
              child: Center(child: CupertinoActivityIndicator()),
            ),
          );
        }
        _cancelRoomDeletedRedirect();
        _hostUid = data['hostUid'] as String?;
        final status = (data['status'] as String?) ?? 'waiting';
        _roomStatus = status;
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
                .map(
                  (e) =>
                      _questionWorkTitle(Map<String, dynamic>.from(e as Map)),
                )
                .where((title) => title.isNotEmpty)
                .toSet()
                .toList();
        final workPool =
            _globalWorkTitlePool.isNotEmpty ? _globalWorkTitlePool : localPool;

        if (status == 'playing' &&
            qs.isNotEmpty &&
            round >= 0 &&
            round < qs.length) {
          _ensureAutoAdvance(widget.roomId, round);
        } else {
          _stopAutoAdvanceWatchers();
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
                  onPressed: () async {
                    final ok = await _confirmLeaveRoom(context);
                    if (ok) await _goLobby();
                  },
                  minimumSize: Size(30, 30),
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
                          onRematchStartByHost: (countHint) async {
                            final qsNew = await _buildQuestions(
                              count:
                                  countHint ?? (qs.isNotEmpty ? qs.length : 5),
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
                          final target = _questionWorkTitle(
                            Map<String, dynamic>.from(qs[round] as Map),
                          );
                          final correct = _match(ans, target);

                          await _svc.submitAnswer(
                            roomId: widget.roomId,
                            roundNo: round,
                            answer: ans,
                            timeMs: timeMs,
                            correct: correct,
                          );

                          // 先に正解しただけでは進めず、時間切れ時のみホストが遷移を確定する。
                          if (isHost && timeUp) {
                            await Future.delayed(
                              const Duration(milliseconds: _REVEAL_HOLD_MS),
                            );
                            final roomDoc = _db
                                .collection('rooms')
                                .doc(widget.roomId);
                            await _advanceToNextRoundOrFinish(
                              roomDoc: roomDoc,
                              expectedRound: round,
                            );
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
  Future<List<Map<String, dynamic>>> _buildQuestions({int count = 5}) async {
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
      double to(x) => (x is num) ? x.toDouble() : double.tryParse('$x') ?? 0.0;
      final workTitle = _resolveWorkTitle(m['workTitle'], fallback: w.id);
      if (workTitle.isEmpty) continue;

      out.add({
        'id': d.id,
        'workKey': w.id,
        'name': m['name'] ?? '',
        'workTitle': workTitle,
        'image': m['image'] ?? '',
        'address': (m['address'] ?? '').toString(),
        'latitude': to(m['latitude']),
        'longitude': to(m['longitude']),
      });
      usedWorks.add(w.id);
      if (out.length >= count) break;
    }

    out.shuffle(rand);
    return out;
  }

  bool _match(String ans, String workTitle) {
    return _sameWorkTitle(ans, workTitle);
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
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
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

  //bool ready が　falseならはじまrない
  Future<void> _setReady(bool ready) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref = _db
        .collection('rooms')
        .doc(widget.roomId)
        .collection('players')
        .doc(uid);
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
        final countdownTs = roomData['publicCountdownStartedAt'] as Timestamp?;
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
                players
                    .where((d) => (d.data()['startReady'] ?? false) == true)
                    .length;
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
                    onPressed:
                        status == 'waiting' ? () => _setReady(!myReady) : null,
                    child: Text(myReady ? '開始を取り消す' : '開始'),
                    //myreadyがtrueなら開始を取り消す、そうでないなら開始にする。
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
  final Future<void> Function(int? countHint) onRematchStartByHost;
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
  bool _rematchStarting = false;
  Timer? _timer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _playersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rematchSub;
  int _remain = _REMATCH_WINDOW_SEC;

  @override
  void initState() {
    super.initState();
    _playersSub = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('players')
        .snapshots()
        .listen((s) => setState(() => _players = s.docs.length));

    _rematchSub = FirebaseFirestore.instance
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

      final everyoneReady =
          widget.isPrivate && _ready > 0 && _players > 0 && _ready >= _players;
      if (everyoneReady) {
        if (widget.isHost) {
          await _startRematchIfNeeded();
        }
        return;
      }

      // タイムアップ → ロビーへ
      if (_remain == 0) {
        _timer?.cancel();
        widget.onGoLobby();
      }
    });
  }

  //timerとwidgetをけしてメモリ還元
  @override
  void dispose() {
    _timer?.cancel();
    _playersSub?.cancel();
    _rematchSub?.cancel();
    super.dispose();
  }

  Future<void> _startRematchIfNeeded() async {
    if (_rematchStarting) return;
    _rematchStarting = true;
    try {
      await widget.onRematchStartByHost(null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _rematchStarting = false);
    }
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
                      onPressed:
                          (widget.isPrivate && !_voted && !_rematchStarting)
                              ? _vote
                              : null,
                      icon: const Icon(Icons.replay),
                      label: Text(
                        widget.isPrivate
                            ? (_rematchStarting
                                ? '再戦準備中…'
                                : (_voted ? '再戦希望済み' : '再戦（全員で押す）'))
                            : '戻る',
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
                        ? '$_remain s 内に全員が押したら再戦'
                        : '$_remain s 後に対戦モード選択へ',
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: widget.onGoLobby,
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('戻る'),
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
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
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
  late final AudioPlayer _resultSfxPlayer;
  bool _playedResultSfx = false;
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
    _resultSfxPlayer = AudioPlayer();
    _listenPlayersCount();
    _setupForRound();
    _listenAnswers();
  }

  @override
  void didUpdateWidget(covariant _PlayPane old) {
    super.didUpdateWidget(old);
    final shouldReset =
        widget.round != old.round ||
        widget.roundStartedAt != old.roundStartedAt ||
        _questionSignature(widget.question) != _questionSignature(old.question);
    if (shouldReset) {
      _playedResultSfx = false;
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
    _resultSfxPlayer.dispose();
    super.dispose();
  }

  Future<void> _playResultSfx(bool isCorrect) async {
    try {
      await _resultSfxPlayer.stop();
      await _resultSfxPlayer.play(
        AssetSource(
          isCorrect ? 'music_dir/quiz_correct.mp3' : 'music_dir/Incorrect.mp3',
        ),
      );
    } catch (_) {
      // no-op
    }
  }

  bool _isCorrectAnswer(String answer) {
    final target = _questionWorkTitle(widget.question);
    return _sameWorkTitle(answer, target);
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
            final title = _questionWorkTitle(widget.question);
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
        _revealTitle ??= _questionWorkTitle(widget.question);
        _roundClosed = true;
        _ticker?.cancel();
        if (!_submitted) _submit(timeUp: true);
      }
    });
  }

  void _prepareChoices() {
    final correct = _questionWorkTitle(widget.question);
    final qid = _trimmedText(
      widget.question['id'] ?? '${widget.question['name']}',
    );
    final rnd = Random(qid.hashCode);
    final pool = widget.workPool.isNotEmpty ? widget.workPool : [correct];
    final correctKey = _normalizeWorkTitle(correct);
    final choicesByKey = <String, String>{};

    if (correct.isNotEmpty && correctKey.isNotEmpty) {
      choicesByKey[correctKey] = correct;
    }

    final shuffledPool = pool.toList()..shuffle(rnd);
    for (final raw in shuffledPool) {
      final candidate = _resolveWorkTitle(raw, fallback: '');
      final key = _normalizeWorkTitle(candidate);
      if (candidate.isEmpty ||
          key.isEmpty ||
          key == correctKey ||
          choicesByKey.containsKey(key)) {
        continue;
      }
      choicesByKey[key] = candidate;
      if (choicesByKey.length >= 4) break;
    }

    var fillerNo = 1;
    while (choicesByKey.length < 4) {
      final filler = '（ダミー）$fillerNo';
      fillerNo++;
      choicesByKey.putIfAbsent(_normalizeWorkTitle(filler), () => filler);
    }

    final list = choicesByKey.values.take(4).toList()..shuffle(rnd);
    var correctIndex = list.indexWhere(
      (choice) => _sameWorkTitle(choice, correct),
    );
    if (correct.isNotEmpty && correctIndex < 0 && list.isNotEmpty) {
      correctIndex = rnd.nextInt(list.length);
      list[correctIndex] = correct;
    }

    setState(() {
      _choices
        ..clear()
        ..addAll(list);
      _correctIndex = correctIndex >= 0 ? correctIndex : null;
      _pickedIndex = null;
      _pause = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    double toD(x) => (x is num) ? x.toDouble() : double.tryParse('$x') ?? 0.0;
    final pos = LatLng(toD(q['latitude']), toD(q['longitude']));

    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;
    final bottomPadding = mq.padding.bottom;
    final isCorrect = _resultText == '正解！';

    // 画面高さに応じて画像・マップの高さを可変に
    final imageHeight = (screenHeight * 0.20).clamp(100.0, 200.0);
    final mapHeight = (screenHeight * 0.18).clamp(90.0, 180.0);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            children: [
              Text(
                '第${widget.round + 1}問 / ${widget.total}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: _remain / widget.roundTimeSec),
              Row(children: [Text('残り $_remain s')]),
              const SizedBox(height: 8),
              if ((q['image'] as String?)?.isNotEmpty == true)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: imageHeight,
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
                height: mapHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GoogleMap(
                    key: ValueKey('round_map_${widget.round}'),
                    initialCameraPosition: CameraPosition(
                      target: pos,
                      zoom: 14,
                    ),
                    markers: {
                      Marker(
                        markerId: MarkerId('m_${widget.round}'),
                        position: pos,
                      ),
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
            ],
          ),
        ),
        // 結果エリア：スクロールせずに常に画面下部へ固定表示
        if (_resultText != null)
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green.shade50 : Colors.red.shade50,
              border: Border(
                top: BorderSide(
                  color:
                      isCorrect ? Colors.green.shade200 : Colors.red.shade200,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _resultText!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isCorrect ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (_revealTitle != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
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
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPadding + 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChoicesArea() {
    if (_choices.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // ボタン高さを画面幅に対して動的に決定（48〜72px に収める）
        final cellWidth = (constraints.maxWidth - 12) / 2;
        final cellHeight = (cellWidth / 3.2).clamp(48.0, 72.0);
        final aspectRatio = cellWidth / cellHeight;
        return GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: aspectRatio,
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
                textAlign: TextAlign.center,
              ),
            );
          }),
        );
      },
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
    if (!_playedResultSfx) {
      final isCorrect = !timeUp && _isCorrectAnswer(send);
      unawaited(_playResultSfx(isCorrect));
      _playedResultSfx = true;
    }
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
