import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'versus_service.dart';

class VersusMatchScreen extends StatefulWidget {
  const VersusMatchScreen({super.key, required this.roomId});
  final String roomId;

  @override
  State<VersusMatchScreen> createState() => _VersusMatchScreenState();
}

class _VersusMatchScreenState extends State<VersusMatchScreen> {
  final _db = FirebaseFirestore.instance;
  final _svc = VersusService();

  // 進行・タイマー
  Timer? _ticker;
  int _totalSec = 0;
  int _remainingSec = 0;
  int _roundStartedAtMs = 0;
  int _pausedRemainingSec = 0;
  bool _paused = false;
  int _lastRound = -1;

  // 入力式
  final _answerCtrl = TextEditingController();
  final _answerFocus = FocusNode();

  // EASY 用：ラウンド→四択
  final Map<int, List<String>> _choicesByRound = {};

  // エフェクト
  bool _fxCorrect = false;
  bool _fxWrong = false;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _roomStream() =>
      _db.collection('rooms').doc(widget.roomId).snapshots();

  @override
  void initState() {
    super.initState();
    _answerFocus.addListener(() => _setPaused(_answerFocus.hasFocus));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _answerCtrl.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  // ───────────────── helpers ─────────────────

  String _readStr(Map<String, dynamic> m, String keyPath) {
    dynamic cur = m;
    for (final k in keyPath.split('.')) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return '';
      }
    }
    return (cur ?? '').toString();
  }

  bool _isEasy(Map<String, dynamic> room) {
    final cand =
        <String>[
          _readStr(room, 'difficulty'),
          _readStr(room, 'level'),
          _readStr(room, 'mode'),
          _readStr(room, 'quizMode'),
          _readStr(room, 'settings.difficulty'),
          _readStr(room, 'settings.mode'),
        ].map((e) => e.toLowerCase()).toSet();
    return cand.contains('easy') ||
        cand.contains('e') ||
        cand.contains('beginner');
  }

  void _setPaused(bool v) {
    if (_paused == v) return;
    setState(() {
      _paused = v;
      if (_paused) {
        _pausedRemainingSec = _remainingSec;
      }
    });
  }

  void _installTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      if (_paused) return; // ★回答中はUIタイマー停止
      final now = DateTime.now().millisecondsSinceEpoch;
      final remainMs = (_roundStartedAtMs + _totalSec * 1000) - now;
      final s = (remainMs / 1000).ceil();
      setState(() => _remainingSec = s.clamp(0, _totalSec));
    });
  }

  void _setupRoundTimer({
    required Timestamp? startedAt,
    required int totalSec,
    required int roundIndex,
  }) {
    _roundStartedAtMs =
        (startedAt?.toDate() ?? DateTime.now()).millisecondsSinceEpoch;
    _totalSec = totalSec;
    _lastRound = roundIndex;

    final now = DateTime.now().millisecondsSinceEpoch;
    final remainMs = (_roundStartedAtMs + _totalSec * 1000) - now;
    _remainingSec = ((remainMs / 1000).ceil()).clamp(0, _totalSec);
    _pausedRemainingSec = _remainingSec;
    _setPaused(false);
    _installTicker();
  }

  // 四択の用意（choices が無いときは自動生成）
  List<String> _buildChoices({
    required Map<String, dynamic> room,
    required Map<String, dynamic> q,
    required int round,
  }) {
    if (_choicesByRound.containsKey(round)) return _choicesByRound[round]!;

    final correct = (q['answer'] ?? '').toString().trim();
    List<String> base =
        ((q['choices'] as List?)?.cast<String>() ?? const [])
            .map((e) => e.trim())
            .toList();

    if (base.isEmpty) {
      final qs =
          (room['questions'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final pool =
          <String>{
            for (final m in qs)
              if ((m['answer'] ?? '').toString().trim().isNotEmpty)
                (m['answer'] as String).trim(),
          }.toList();
      pool.removeWhere((e) => e == correct);
      pool.shuffle();
      base = [correct, ...pool.take(3)];
    }

    // 重複除去 + 足し込み
    final used = <String>{};
    final out = <String>[];
    for (final c in base) {
      if (c.isEmpty) continue;
      if (used.add(c)) out.add(c);
    }
    if (!used.contains(correct)) out.insert(0, correct);
    while (out.length < 4) {
      final alt = '$correct ';
      if (used.add(alt)) out.add(alt);
      if (out.length >= 4) break;
      final alt2 = ' $correct';
      if (used.add(alt2)) out.add(alt2);
    }

    out.shuffle();
    _choicesByRound[round] = out;
    return out;
  }

  // 回答送信 + 早押し判定
  Future<void> _submitAnswer({
    required Map<String, dynamic> room,
    required int round,
    required String answer,
    required bool isCorrect,
  }) async {
    _setPaused(true);

    try {
      final elapsedMs =
          (_totalSec - (_paused ? _pausedRemainingSec : _remainingSec)) * 1000;
      await _svc.submitAnswer(
        roomId: widget.roomId,
        roundNo: round,
        answer: answer,
        timeMs: elapsedMs.clamp(0, _totalSec * 1000),
        correct: isCorrect,
      );

      if (isCorrect) {
        setState(() => _fxCorrect = true);
        // 誰かが最初に正解したら、その場で答え公開→次へ（Tx で取り合い）
        final correctText =
            (room['questions'][round]['answer'] ?? '').toString();
        await _svc.tryFinishRoundOnFirstCorrect(
          roomId: widget.roomId,
          roundNo: round,
          correctAnswer: correctText,
        );
      } else {
        setState(() => _fxWrong = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('送信に失敗: $e')));
    } finally {
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() {
        _fxCorrect = false;
        _fxWrong = false;
        _setPaused(false);
      });
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _roomStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _Scaffold(
            title: '対戦ルーム',
            child: Center(child: Text('エラー: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return const _Scaffold(
            title: '対戦ルーム',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final room = snap.data!.data();
        if (room == null) {
          return const _Scaffold(
            title: '対戦ルーム',
            child: Center(child: Text('ルームが見つかりません')),
          );
        }

        final questions =
            (room['questions'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        final round = (room['round'] ?? 0) as int;
        final total = questions.length;
        final startedAt = room['roundStartedAt'] as Timestamp?;
        final roundTimeSec = (room['roundTimeSec'] ?? 20) as int;

        // ラウンド切替時に初期化
        if (_lastRound != round || _totalSec != roundTimeSec) {
          _choicesByRound.remove(round); // 念のため再生成
          _setupRoundTimer(
            startedAt: startedAt,
            totalSec: roundTimeSec,
            roundIndex: round,
          );
        }

        final isEasy = _isEasy(room);
        final current = (round >= 0 && round < total) ? questions[round] : null;
        final firstCorrect =
            room['firstCorrect']
                as Map<String, dynamic>?; // {round, answer, by, at}

        return _Scaffold(
          title: '対戦ルーム',
          trailing: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text('招待: ${(room['code'] ?? '').toString()}'),
          ),
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Text(
                        (current == null) ? '準備中…' : '第${round + 1}問 / $total',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _paused ? '一時停止中' : '残り ${_remainingSec}s',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value:
                        _paused || _totalSec == 0
                            ? null
                            : _remainingSec / _totalSec,
                    minHeight: 4,
                  ),
                  const SizedBox(height: 16),

                  if (current != null &&
                      (current['image'] as String?)?.isNotEmpty == true)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          current['image'],
                          fit: BoxFit.cover,
                          loadingBuilder:
                              (c, child, p) =>
                                  p == null
                                      ? child
                                      : const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                          errorBuilder:
                              (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                ),
                              ),
                        ),
                      ),
                    ),

                  if (current != null &&
                      (current['spot'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text('スポット: ${current['spot']}'),
                  ],

                  const SizedBox(height: 16),

                  if (current != null)
                    _buildAnswerArea(
                      room: room,
                      q: current,
                      round: round,
                      isEasy: isEasy,
                      firstCorrect: firstCorrect,
                    ),

                  if (firstCorrect != null &&
                      (firstCorrect['round'] ?? -1) == round) ...[
                    const SizedBox(height: 16),
                    _AnswerReveal(
                      answer: (firstCorrect['answer'] ?? '').toString(),
                    ),
                  ],
                ],
              ),

              // 正解/不正解エフェクト
              IgnorePointer(
                ignoring: true,
                child: AnimatedOpacity(
                  opacity: _fxCorrect ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: _FxOverlay(
                    icon: Icons.check_circle,
                    color: Colors.greenAccent.withOpacity(0.85),
                  ),
                ),
              ),
              IgnorePointer(
                ignoring: true,
                child: AnimatedOpacity(
                  opacity: _fxWrong ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: _FxOverlay(
                    icon: Icons.close_rounded,
                    color: Colors.redAccent.withOpacity(0.85),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnswerArea({
    required Map<String, dynamic> room,
    required Map<String, dynamic> q,
    required int round,
    required bool isEasy,
    required Map<String, dynamic>? firstCorrect,
  }) {
    final solvedNow =
        firstCorrect != null && (firstCorrect['round'] ?? -1) == round;
    final correctText = (q['answer'] ?? '').toString().trim();

    // すでに誰かが正解 → 受け付けず表示だけ
    if (solvedNow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '正解：$correctText',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('次の問題へ移行します…'),
        ],
      );
    }

    // EASY: 四択
    if (isEasy) {
      final choices = _buildChoices(room: room, q: q, round: round);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('選択肢から選んでください（EASY 四択）'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in choices)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 16 * 2 - 8) / 2,
                  child: ElevatedButton(
                    onPressed:
                        () => _submitAnswer(
                          room: room,
                          round: round,
                          answer: c,
                          isCorrect: c.trim() == correctText,
                        ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        c,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    // 通常：入力式（フォーカス中は一時停止）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('アニメ作品名を入力'),
        const SizedBox(height: 8),
        TextField(
          controller: _answerCtrl,
          focusNode: _answerFocus,
          textInputAction: TextInputAction.done,
          onSubmitted:
              (_) => _submitAnswer(
                room: room,
                round: round,
                answer: _answerCtrl.text.trim(),
                isCorrect: _answerCtrl.text.trim() == correctText,
              ),
          decoration: const InputDecoration(
            hintText: '例）○○○○',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed:
              () => _submitAnswer(
                room: room,
                round: round,
                answer: _answerCtrl.text.trim(),
                isCorrect: _answerCtrl.text.trim() == correctText,
              ),
          icon: const Icon(Icons.send),
          label: const Text('回答'),
        ),
      ],
    );
  }
}

// ──────────────── 細かい UI パーツ ────────────────

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [if (trailing != null) trailing!],
      ),
      body: child,
    );
  }
}

class _AnswerReveal extends StatelessWidget {
  const _AnswerReveal({required this.answer});
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text('正解：$answer')),
        ],
      ),
    );
  }
}

class _FxOverlay extends StatelessWidget {
  const _FxOverlay({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Icon(icon, size: 120, color: Colors.white),
    );
  }
}
