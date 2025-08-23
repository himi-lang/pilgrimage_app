import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // 使っていなければ消してOK
import 'versus_service.dart';

// ▼ 適切な方を1本だけ残す（このファイルが lib/versus/ にあるなら下、直下なら上）
import '../widgets/app_ui.dart';
// import 'widgets/app_ui.dart';

class VersusLobbyScreen extends StatefulWidget {
  const VersusLobbyScreen({super.key});
  @override
  State<VersusLobbyScreen> createState() => _VersusLobbyScreenState();
}

class _VersusLobbyScreenState extends State<VersusLobbyScreen> {
  final s = VersusService();
  String difficulty = 'normal';
  final codeCtrl = TextEditingController();
  bool busy = false; // 連打ガード

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: commonAppBar(context, title: '対戦ロビー'), // ← 共通ログアウトつき
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'easy', label: Text('Easy')),
                ButtonSegment(value: 'normal', label: Text('Normal')),
                ButtonSegment(value: 'hard', label: Text('Hard')),
              ],
              selected: {difficulty},
              onSelectionChanged: (v) => setState(() => difficulty = v.first),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  busy
                      ? null
                      : () async {
                        setState(() => busy = true);
                        final id = await s.quickJoin(difficulty: difficulty);
                        if (!mounted) return;
                        setState(() => busy = false);
                        Navigator.pushReplacementNamed(
                          context,
                          '/versus/room/$id',
                        );
                      },
              icon: const Icon(Icons.flash_on),
              label: Text(busy ? '接続中…' : 'クイックマッチ'),
            ),
            const Divider(height: 32),
            Text('プライベートマッチ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        busy
                            ? null
                            : () async {
                              setState(() => busy = true);
                              final id = await s.createRoom(
                                isPrivate: true,
                                difficulty: difficulty,
                              );
                              if (!mounted) return;
                              setState(() => busy = false);
                              Navigator.pushReplacementNamed(
                                context,
                                '/versus/room/$id',
                              );
                            },
                    icon: const Icon(Icons.lock),
                    label: const Text('部屋を作る'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      hintText: '招待コード6桁',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed:
                      busy
                          ? null
                          : () async {
                            final code = codeCtrl.text.trim().toUpperCase();
                            if (code.length != 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('6桁のコードを入力してください'),
                                ),
                              );
                              return;
                            }
                            setState(() => busy = true);
                            final id = await s.joinByCode(code);
                            if (!mounted) return;
                            setState(() => busy = false);
                            if (id == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('見つかりませんでした')),
                              );
                            } else {
                              Navigator.pushReplacementNamed(
                                context,
                                '/versus/room/$id',
                              );
                            }
                          },
                  child: const Text('参加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
