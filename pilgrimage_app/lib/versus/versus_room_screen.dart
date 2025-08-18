import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  final _sw = Stopwatch();

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
        final status = data['status'] as String;
        final round = (data['round'] ?? 0) as int;
        final List qs = (data['questions'] ?? []) as List;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              '部屋 ${widget.roomId.substring(0, 5)}… ${status.toUpperCase()}',
            ),
            actions: [
              if (data['code'] != null && (data['code'] as String).isNotEmpty)
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
                child:
                    status == 'waiting'
                        ? _WaitingPane(
                          isHost: isHost,
                          onStart: () async {
                            final questions = await _buildQuestions(
                              data['difficulty'] ?? 'normal',
                              count: 5,
                            );
                            await _svc.startMatch(widget.roomId, questions);
                          },
                        )
                        : _PlayPane(
                          question: qs[round],
                          round: round,
                          total: qs.length,
                          onSubmit: (ans, timeMs) async {
                            final correct = _match(
                              ans,
                              (qs[round]['workTitle'] ?? '') as String,
                            );
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
                        ),
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
    // 既存の Firestore 構造（聖地情報/作品/聖地）からランダム抽出（簡易）
    // 1) 作品をいくつか拾う → 2) 各作品の聖地を少し取り、ローカルでシャッフル
    final worksSnap = await _db.collection('聖地情報').limit(5).get();
    final rand = Random();
    final List<Map<String, dynamic>> out = [];
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
        out.add({
          'id': d.id,
          'name': m['name'] ?? '',
          'workTitle': m['workTitle'] ?? w.id,
          'image': m['image'] ?? '',
          'latitude':
              (m['latitude'] is num)
                  ? (m['latitude'] as num).toDouble()
                  : double.tryParse('${m['latitude']}') ?? 0,
          'longitude':
              (m['longitude'] is num)
                  ? (m['longitude'] as num).toDouble()
                  : double.tryParse('${m['longitude']}') ?? 0,
        });
      }
    }
    out.shuffle(rand);
    return out.take(count).toList();
  }

  bool _match(String ans, String workTitle) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r"[\s　]"), '');
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
      height: 92,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ref.orderBy('joinedAt').snapshots(),
        builder: (c, s) {
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemBuilder: (_, i) {
              final d = docs[i].data();
              return Column(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage:
                        d['photoURL'] != null
                            ? NetworkImage(d['photoURL'])
                            : null,
                    child:
                        d['photoURL'] == null ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (d['displayName'] ?? 'Player'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Score ${d['score'] ?? 0}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemCount: docs.length,
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
  final _sw = Stopwatch();
  @override
  void initState() {
    super.initState();
    _sw
      ..reset()
      ..start();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final lat = (q['latitude'] ?? 0).toDouble();
    final lng = (q['longitude'] ?? 0).toDouble();
    final pos = LatLng(lat, lng);

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
          if ((q['image'] ?? '').toString().isNotEmpty)
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
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              hintText: 'アニメ作品名を入力（例: 色づく世界の明日から）',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () async {
                  _sw.stop();
                  await widget.onSubmit(
                    _ctrl.text.trim(),
                    _sw.elapsedMilliseconds,
                  );
                },
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
}
