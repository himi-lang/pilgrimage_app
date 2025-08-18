import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'versus_service.dart';

class VersusLobbyScreen extends StatefulWidget {
  const VersusLobbyScreen({super.key});
  @override
  State<VersusLobbyScreen> createState() => _VersusLobbyScreenState();
}

class _VersusLobbyScreenState extends State<VersusLobbyScreen> {
  final s = VersusService();
  String difficulty = 'normal';
  final codeCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('対戦ロビー')),
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
              onPressed: () async {
                final id = await s.quickJoin(difficulty: difficulty);
                if (!mounted) return;
                Navigator.pushReplacementNamed(context, '/versus/room/$id');
              },
              icon: const Icon(Icons.flash_on),
              label: const Text('クイックマッチ'),
            ),
            const Divider(height: 32),
            Text('プライベートマッチ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final id = await s.createRoom(
                        isPrivate: true,
                        difficulty: difficulty,
                      );
                      if (!mounted) return;
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
                    decoration: const InputDecoration(hintText: '招待コード6桁'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final id = await s.joinByCode(codeCtrl.text.trim());
                    if (id == null) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('見つかりませんでした')),
                      );
                    } else {
                      if (!mounted) return;
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
