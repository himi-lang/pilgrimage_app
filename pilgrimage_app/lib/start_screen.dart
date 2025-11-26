// lib/start_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_screen.dart';
import 'mode_selection_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  Future<void> _handleTap(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // 未ログイン → ログイン画面へ
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      // ログイン済み → そのままモード選択へ
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ModeSelectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 背景画像
            Image.asset(
              'image_dir/test1.jpg', // ← あとで差し替えてOK
              fit: BoxFit.cover,
            ),
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
    );
  }
}
