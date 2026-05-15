// lib/start_screen.dart
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_screen.dart';
import 'mode_selection_screen.dart';
import 'service/app_audio_service.dart';
import 'terms_screen.dart';
import 'service/terms_service.dart';

const Duration _screenFadeDuration = Duration(milliseconds: 600);

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  double _opacity = 1.0; //フェード用
  bool _isProcessing = false; //連打防止

  @override
  void initState() {
    super.initState();
    AppAudioService.instance.fadeOutScreenBgm(
      duration: const Duration(milliseconds: 300),
    );
    AppAudioService.instance.playStartSound();
  }

  Future<void> _handleTap() async {
    if (_isProcessing) return;
    _isProcessing = true;

    final termsFuture = TermsService.shouldShowTerms();

    // ① 画面遷移のフェードアウト開始
    setState(() {
      _opacity = 0.0;
    });
    AppAudioService.instance.fadeOutStartSound(duration: _screenFadeDuration);

    // ② フェードが終わるまで少し待つ（AnimatedOpacity と合わせる）
    await Future.delayed(_screenFadeDuration);
    if (!mounted) return;

    // ③ ここから先は元の処理（利用規約 → ログイン判定）
    final needTerms = await termsFuture;
    if (!mounted) return;

    if (needTerms) {
      final accepted =
          await Navigator.of(context).push<bool>(
            CupertinoPageRoute(builder: (_) => const TermsScreen()),
          ) ??
          false;

      if (!accepted) {
        _isProcessing = false;
        // 利用規約に同意しなかったときはフェードを戻しておく
        if (!mounted) return;
        setState(() {
          _opacity = 1.0;
        });
        AppAudioService.instance.playStartSound();
        return;
      }
    }
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // 未ログイン → ログイン画面へ
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      // ログイン済み → モード選択へ
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(builder: (_) => const ModeSelectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black, // ★ フェード後は黒背景に
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: _screenFadeDuration,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景画像
              Image.asset(
                'assets/image_dir/main_visual.jpg',
                fit: BoxFit.cover,
              ),

              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: Colors.black.withValues(alpha: 0.20)),
              ),

              Center(
                child: Image.asset(
                  "assets/image_dir/main_visual.jpg",
                  fit: BoxFit.contain,
                ),
              ),
              // うっすら暗くするレイヤー
              Container(color: Colors.black.withValues(alpha: 0.25)),

              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Text(
                        "タップしてスタート",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          letterSpacing: 2,
                          decoration: TextDecoration.none,
                        ),
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
