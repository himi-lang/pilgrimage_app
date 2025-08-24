import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/app_ui.dart';
import 'versus_service.dart';

// === ログと遷移ディレイの設定 ===
const bool _MUTE_SNACK = true; // true: SnackBarを出さない
const int _REVEAL_HOLD_MS = 3000; // 解答表示→次問題までの待機(ms)

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

  // --- オート進行監視 ---
  StreamSubscription? _autoAnsSub;
  StreamSubscription? _autoPlayersSub;
  int _playersCount = 0;
  int? _watchingRound;
  bool _advancedThisRound = false;

  // --- 四択のグローバルプール ---
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

  // 開始
  Future<void> _handleStart(Map<String, dynamic> data) async {
    try {
      if (!mounted) return;
      if (!_MUTE_SNACK) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('問題を読み込み中…')));
      }

      final qs = await _buildQuestions(
        data['difficulty'] ?? 'normal',
        count: 5,
      );
      if (qs.isEmpty) {
        if (!mounted) return;
        if (!_MUTE_SNACK) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('問題データが見つかりません（聖地情報コレクションを確認してください）')),
          );
        }
        return;
      }
      await _svc.startMatch(widget.roomId, qs);

      if (!mounted) return;
      if (!_MUTE_SNACK) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('対戦を開始しました')));
      }
    } catch (e) {
      if (!mounted) return;
      if (!_MUTE_SNACK) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('開始に失敗: $e')));
      }
    }
  }

  // ホストの自動遷移（誰か正解 or 全員回答）
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
          final anyCorrect = docs.any(
            (d) => (d.data()['correct'] ?? false) == true,
          );
          final allAnswered =
              (_playersCount > 0) && (docs.length >= _playersCount);

          if (anyCorrect || allAnswered) {
            _advancedThisRound = true;
            // 表示を見せるための待機
            await Future.delayed(const Duration(milliseconds: _REVEAL_HOLD_MS));

            // まだ同じラウンドなら進行
            final snap = await roomDoc.get();
            final data = snap.data();
            if (data == null) return;
            final cur = (data['round'] ?? 0) as int;
            if (cur != round) return;
            final qs = (data['questions'] ?? []) as List;
            if (cur < qs.length - 1) {
              await _svc.nextRound(roomId, cur + 1);
            } else {
              await roomDoc.update({'status': 'finished'});
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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data!.data();
        if (data == null) {
          return const Scaffold(body: Center(child: Text('部屋が削除されました')));
        }
        _hostUid = data['hostUid'] as String?;
        final status = (data['status'] as String?) ?? 'waiting';
        final round = (data['round'] ?? 0) as int;
        final List qs = (data['questions'] ?? []) as List;
        final int roundTimeSec = (data['roundTimeSec'] ?? 20) as int;
        final String difficulty = (data['difficulty'] ?? 'normal') as String;
        final DateTime? roundStartedAt =
            (data['roundStartedAt'] as Timestamp?)?.toDate();

        // easy用プール（グローバル→ローカルの順で採用）
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
          child: Scaffold(
            appBar: commonAppBar(
              context,
              title: '対戦ルーム',
              currentMode: AppMode.versus,
              actionsExtra: [
                if ((data['code'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Text(
                        '招待: ${data['code']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
              modeConfirm: () => _confirmLeaveRoom(context),
              modeBeforeNavigate: () => _svc.leaveRoom(widget.roomId),
            ),
            body: Column(
              children: [
                _PlayersList(roomId: widget.roomId),
                const Divider(height: 1),
                Expanded(
                  child: () {
                    if (status == 'waiting') {
                      return _WaitingPane(
                        isHost: isHost,
                        onStart: () => _handleStart(data),
                      );
                    }
                    if (status == 'finished' ||
                        qs.isEmpty ||
                        round < 0 ||
                        round >= qs.length) {
                      return _FinishedPane(roomId: widget.roomId);
                    }
                    return _PlayPane(
                      roomId: widget.roomId,
                      question: Map<String, dynamic>.from(qs[round] as Map),
                      round: round,
                      total: qs.length,
                      roundTimeSec: roundTimeSec,
                      roundStartedAt: roundStartedAt,
                      difficulty: difficulty,
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

                        // 集計用
                        final uid =
                            FirebaseAuth.instance.currentUser?.uid ?? '';
                        await _db
                            .collection('rooms')
                            .doc(widget.roomId)
                            .collection('answers')
                            .doc('$round-$uid')
                            .set({
                              'round': round,
                              'uid': uid,
                              'correct': correct,
                              'createdAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));

                        // 互換：ホストが直接進める経路にも待機を入れる
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
                            await roomDoc.update({'status': 'finished'});
                          }
                        }
                      },
                    );
                  }(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 多様性を高めた出題：作品重複なし
  Future<List<Map<String, dynamic>>> _buildQuestions(
    String difficulty, {
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

class _FinishedPane extends StatelessWidget {
  final String roomId;
  const _FinishedPane({required this.roomId});
  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomId)
        .collection('players')
        .orderBy('score', descending: true);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
    );
  }
}

class _PlayPane extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic> question;
  final int round;
  final int total;
  final int roundTimeSec;
  final DateTime? roundStartedAt;
  final String difficulty; // 'easy'|'normal'|'hard'
  final List<String> workPool;
  final Future<void> Function(String ans, int timeMs, {bool timeUp}) onSubmit;

  const _PlayPane({
    required this.roomId,
    required this.question,
    required this.round,
    required this.total,
    required this.roundTimeSec,
    required this.roundStartedAt,
    required this.difficulty,
    required this.workPool,
    required this.onSubmit,
  });
  @override
  State<_PlayPane> createState() => _PlayPaneState();
}

class _PlayPaneState extends State<_PlayPane> {
  final _ctrl = TextEditingController();
  late Stopwatch _sw;
  bool _submitted = false;
  late int _remain;
  Timer? _ticker;

  // easy
  final List<String> _choices = [];
  int? _correctIndex;
  int? _pickedIndex;
  bool _pause = false;
  bool get _isEasy => widget.difficulty == 'easy';

  // 表示
  String? _revealTitle;
  String? _resultText;

  StreamSubscription? _answersSub;
  int _playersCount = 0;
  int _answersCount = 0;
  int _correctCount = 0;

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
    _listenPlayersCount();
    _setupForRound(first: true);
    _listenAnswers();
  }

  @override
  void didUpdateWidget(covariant _PlayPane old) {
    super.didUpdateWidget(old);
    if (widget.round != old.round) {
      _submitted = false;
      _revealTitle = null;
      _resultText = null;
      _ctrl.clear();
      _sw
        ..reset()
        ..start();
      _setupForRound();
      _listenAnswers();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
          _correctCount = s.docs.where((d) => (d['correct'] == true)).length;
          if (_playersCount > 0 &&
              _answersCount >= _playersCount &&
              (_correctCount == 0 || _correctCount == _playersCount)) {
            final title = (widget.question['workTitle'] ?? '') as String;
            if (_revealTitle != title) {
              setState(() => _revealTitle = title);
            }
          }
        });
  }

  void _setupForRound({bool first = false}) {
    _setupTimer();
    if (_isEasy) _prepareChoices();
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
    while (set.length < 4) {
      set.add('（ダミー）${set.length}');
    }
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
    final hard = widget.difficulty == 'hard';
    final halfPassed = _remain <= (widget.roundTimeSec ~/ 2);
    final hint = (q['address'] as String?)?.trim();

    // ★ Column → ListView に変更（オーバーフロー対策）
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
            const Spacer(),
            if (hard && halfPassed && (hint?.isNotEmpty ?? false))
              Text('ヒント: $hint', overflow: TextOverflow.ellipsis),
          ],
        ),
        const SizedBox(height: 8),
        if ((q['image'] as String?)?.isNotEmpty == true)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(q['image'], height: 180, fit: BoxFit.cover),
          ),
        const SizedBox(height: 8),
        if (!hard)
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
              initialCameraPosition: CameraPosition(target: pos, zoom: 14),
              markers: {Marker(markerId: const MarkerId('m'), position: pos)},
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              liteModeEnabled: true,
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (_isEasy) _buildChoicesArea() else _buildTypingArea(),

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

        // 端末のナビバー分だけゆとり
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );
  }

  // easy: 四択（1回だけ）
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
              (_submitted || _pickedIndex != null) ? null : () => _onPick(i),
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
    if (_submitted || _pickedIndex != null) return;
    setState(() {
      _pause = true;
      _pickedIndex = index;
    });

    final isCorrect = (index == _correctIndex);
    _resultText = isCorrect ? '正解！' : '不正解…';

    await _submit(ans: _choices[index]); // 集計に送る
    if (mounted) setState(() => _pause = false);
  }

  // normal/hard: 手入力（1回だけ）
  Widget _buildTypingArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _submit(),
          enabled: !_submitted,
          decoration: const InputDecoration(hintText: 'アニメ作品名を入力'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _submitted ? null : _submit,
          child: const Text('回答'),
        ),
      ],
    );
  }

  Future<void> _submit({String? ans, bool timeUp = false}) async {
    if (_submitted && !timeUp) return; // 回答は一度だけ（timeUp通知は通す）
    if (!timeUp) _submitted = true;
    _sw.stop();
    final send = ans ?? _ctrl.text.trim();

    await widget.onSubmit(send, _sw.elapsedMilliseconds, timeUp: timeUp);

    if (!mounted) return;
    if (!_MUTE_SNACK && !timeUp) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回答を送信しました')));
    }
    setState(() {}); // 反映
  }
}
