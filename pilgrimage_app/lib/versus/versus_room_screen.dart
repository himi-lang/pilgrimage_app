import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/app_ui.dart'; // 共通AppBar/Logout
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
  final _ansCtrl = TextEditingController();

  bool get isHost => _hostUid == _auth.currentUser?.uid;
  String? _hostUid;

  @override
  void dispose() {
    _ansCtrl.dispose();
    super.dispose();
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
        final data = snap.data!.data()!;
        _hostUid = data['hostUid'];
        final status = (data['status'] as String?) ?? 'waiting';
        final round = (data['round'] ?? 0) as int;
        final List qs = (data['questions'] ?? []) as List;

        return Scaffold(
          appBar: commonAppBar(
            context,
            title: '対戦ルーム',
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
                      onStart: () async {
                        final questions = await _buildQuestions(
                          data['difficulty'] ?? 'normal',
                          count: 5,
                        );
                        await _svc.startMatch(widget.roomId, questions);
                      },
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
                        await _db.collection('rooms').doc(widget.roomId).update(
                          {'status': 'finished'},
                        );
                      }
                    },
                  );
                }(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _buildQuestions(
    String difficulty, {
    int count = 5,
  }) async {
    // Firestoreの既存データから簡易抽出（MVP）
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
      height: 96,
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
                  Text(
                    'Score ${d['score'] ?? 0}',
                    style: const TextStyle(fontSize: 12),
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
  final Future<void> Function(String ans, int timeMs) onSubmit;
  const _PlayPane({
    required this.question,
    required this.round,
    required this.total,
    required this.onSubmit,
  });
  @override
  State<_PlayPane> createState() => _PlayPaneState();
}

class _PlayPaneState extends State<_PlayPane> {
  final _ctrl = TextEditingController();
  late Stopwatch _sw;
  bool _submitted = false; // 送信連打防止

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
  }

  @override
  void didUpdateWidget(covariant _PlayPane old) {
    super.didUpdateWidget(old);
    if (widget.round != old.round) {
      _submitted = false;
      _ctrl.clear();
      _sw
        ..reset()
        ..start(); // ラウンド切替時に計測と入力をリセット
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    double _toD(x) => (x is num) ? x.toDouble() : double.tryParse('$x') ?? 0.0;
    final pos = LatLng(_toD(q['latitude']), _toD(q['longitude']));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第${widget.round + 1}問 / ${widget.total}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if ((q['image'] as String?)?.isNotEmpty == true)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(q['image'], height: 180, fit: BoxFit.cover),
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
                initialCameraPosition: CameraPosition(target: pos, zoom: 14),
                markers: {Marker(markerId: const MarkerId('m'), position: pos)},
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                liteModeEnabled: true, // 軽量表示
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
