import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/app_ui.dart';
import 'versus_service.dart';

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

  // 開始ボタンの処理（例外可視化・問題0件検知）
  Future<void> _handleStart(Map<String, dynamic> data) async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('問題を読み込み中…')));

      final qs = await _buildQuestions(
        data['difficulty'] ?? 'normal',
        count: 5,
      );
      if (qs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('問題データが見つかりません（聖地情報コレクションを確認してください）')),
        );
        return;
      }

      await _svc.startMatch(widget.roomId, qs);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('対戦を開始しました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('開始に失敗: $e')));
    }
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
                      question: Map<String, dynamic>.from(qs[round] as Map),
                      round: round,
                      total: qs.length,
                      roundTimeSec: roundTimeSec,
                      roundStartedAt: roundStartedAt,
                      difficulty: difficulty,
                      onSubmit: (ans, timeMs) async {
                        final target = (qs[round]['workTitle'] ?? '') as String;
                        final correct = _match(ans, target);
                        await _svc.submitAnswer(
                          roomId: widget.roomId,
                          roundNo: round,
                          answer: ans,
                          timeMs: timeMs,
                          correct: correct,
                        );
                        if (isHost && round < qs.length - 1) {
                          await _svc.nextRound(widget.roomId, round + 1);
                        } else if (isHost && round == qs.length - 1) {
                          await _db
                              .collection('rooms')
                              .doc(widget.roomId)
                              .update({'status': 'finished'});
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

  Future<List<Map<String, dynamic>>> _buildQuestions(
    String difficulty, {
    int count = 5,
  }) async {
    // 既存データから簡易抽出
    final worksSnap = await _db.collection('聖地情報').limit(5).get();
    final rand = Random();
    final out = <Map<String, dynamic>>[];
    for (final w in worksSnap.docs) {
      final spots =
          await _db
              .collection('聖地情報')
              .doc(w.id)
              .collection('聖地')
              .limit(10)
              .get();
      final list = spots.docs.toList()..shuffle(rand);
      for (final d in list.take(2)) {
        final m = d.data();
        double _toDyn(x) =>
            (x is num) ? x.toDouble() : double.tryParse('$x') ?? 0.0;
        out.add({
          'id': d.id,
          'name': m['name'] ?? '',
          'workTitle': m['workTitle'] ?? w.id,
          'image': m['image'] ?? '',
          'address': (m['address'] ?? '').toString(),
          'latitude': _toDyn(m['latitude']),
          'longitude': _toDyn(m['longitude']),
        });
      }
    }
    out.shuffle(rand);
    return out.take(count).toList();
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
      height: 110, // はみ出し防止で拡張
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
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
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
  final Map<String, dynamic> question;
  final int round;
  final int total;
  final int roundTimeSec;
  final DateTime? roundStartedAt;
  final String difficulty; // 'easy'|'normal'|'hard'
  final Future<void> Function(String ans, int timeMs) onSubmit;
  const _PlayPane({
    required this.question,
    required this.round,
    required this.total,
    required this.roundTimeSec,
    required this.roundStartedAt,
    required this.difficulty,
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

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
    _setupTimer();
  }

  @override
  void didUpdateWidget(covariant _PlayPane old) {
    super.didUpdateWidget(old);
    if (widget.round != old.round) {
      _submitted = false;
      _ctrl.clear();
      _sw
        ..reset()
        ..start();
      _setupTimer();
    }
  }

  void _setupTimer() {
    _ticker?.cancel();
    final start = widget.roundStartedAt ?? DateTime.now();
    _remain = widget.roundTimeSec - DateTime.now().difference(start).inSeconds;
    if (_remain < 0) _remain = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remain = (_remain - 1).clamp(0, widget.roundTimeSec));
      if (_remain == 0) {
        _ticker?.cancel();
        if (!_submitted) _submit();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    double _toD(x) => (x is num) ? x.toDouble() : double.tryParse('$x') ?? 0.0;
    final pos = LatLng(_toD(q['latitude']), _toD(q['longitude']));
    final hard = widget.difficulty == 'hard';
    final halfPassed = _remain <= (widget.roundTimeSec ~/ 2);
    final hint = (q['address'] as String?)?.trim();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(hintText: 'アニメ作品名を入力'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: _submitted ? null : _submit,
                child: const Text('回答'),
              ),
              const Spacer(),
              Text('${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitted) return;
    _submitted = true;
    _sw.stop();
    final ans = _ctrl.text.trim();
    await widget.onSubmit(ans, _sw.elapsedMilliseconds);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回答を送信しました')));
      setState(() {}); // ボタン無効の反映
    }
  }
}
