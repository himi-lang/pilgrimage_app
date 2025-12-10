import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
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
  bool _busy = false;

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _quickMatch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await s.quickJoin(difficulty: difficulty);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/versus/room/$id');
    } catch (e) {
      _toast('クイックマッチに失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createPrivate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await s.createRoom(isPrivate: true, difficulty: difficulty);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/versus/room/$id');
    } catch (e) {
      _toast('部屋の作成に失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinByCode() async {
    if (_busy) return;
    final raw = codeCtrl.text.trim().toUpperCase();
    if (raw.length != 6) {
      _toast('招待コードは6桁です');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await s.joinByCode(raw);
      if (id == null) {
        _toast('見つかりませんでした（コード・開始済み・終了の可能性）');
      } else {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/versus/room/$id');
      }
    } catch (e) {
      _toast('参加に失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: commonAppBar(
        context,
        title: '対戦ロビー',
        currentMode: AppMode.versus,
      ),
      body: Container(
        // ★ 背景画像
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/image_dir/tokyo_tower.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        // 背景の上にうっすら白をかぶせて内容を載せる
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white.withOpacity(0.85), // 0.7〜0.9くらいで好み調整
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'easy', label: Text('Easy')),
                  //ButtonSegment(value: 'normal', label: Text('Normal')),
                  //ButtonSegment(value: 'hard', label: Text('Hard')),
                ],
                selected: {difficulty},
                onSelectionChanged: (v) => setState(() => difficulty = v.first),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _quickMatch,
                icon: const Icon(Icons.flash_on),
                label: Text(_busy ? '接続中…' : 'クイックマッチ'),
              ),
              const Divider(height: 32),
              Text('プライベートマッチ', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _createPrivate,
                icon: const Icon(Icons.lock),
                label: const Text('部屋を作る'),
                style: OutlinedButton.styleFrom(foregroundColor: cs.onSurface),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: '招待コード6桁'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _joinByCode,
                    child: const Text('参加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
