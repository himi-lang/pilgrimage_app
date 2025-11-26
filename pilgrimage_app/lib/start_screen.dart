// lib/start_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';

import 'login_screen.dart';
import 'mode_selection_screen.dart';
import 'terms_screen.dart';
import 'service/terms_service.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final AudioPlayer _player;
  double _opacity = 1.0; // ★ フェード用
  bool _isProcessing = false; // ★ 連打防止

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isProcessing) return;
    _isProcessing = true;

    // ① 効果音
    _player.play(AssetSource('music_dir/tear_drop.mp3'));

    // ② フェードアウト開始
    setState(() {
      _opacity = 0.0;
    });

    // ③ フェードが終わるまで少し待つ（AnimatedOpacity と合わせる）
    await Future.delayed(const Duration(milliseconds: 600));

    // ④ ここから先は元の処理（利用規約 → ログイン判定）
    final needTerms = await TermsService.shouldShowTerms();

    if (needTerms) {
      final accepted =
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const TermsScreen()),
          ) ??
          false;

      if (!accepted) {
        _isProcessing = false;
        // 利用規約に同意しなかったときはフェードを戻しておく
        setState(() {
          _opacity = 1.0;
        });
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // 未ログイン → ログイン画面へ
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      // ログイン済み → モード選択へ
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ModeSelectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // ★ フェード後は黒背景に
      body: GestureDetector(
        onTap: _handleTap,
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 600),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景画像
              Image.asset('assets/image_dir/test1.jpg', fit: BoxFit.cover),
              // うっすら暗くするレイヤー
              Container(color: Colors.black.withOpacity(0.25)),
              // 「タップしてスタート」の帯
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text(
                      'タップしてスタート',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
