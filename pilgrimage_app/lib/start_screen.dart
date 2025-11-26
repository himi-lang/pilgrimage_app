// lib/start_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_screen.dart';
import 'mode_selection_screen.dart';
import 'terms_screen.dart'; // ★ 追加
import 'service/terms_service.dart'; // ★ 追加

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  Future<void> _handleTap(BuildContext context) async {
    // ① 今のバージョンの利用規約を出す必要があるかチェック
    final needTerms = await TermsService.shouldShowTerms();

    if (needTerms) {
      // ② 必要なら利用規約画面を開いて、同意したかどうか(bool)を受け取る
      final accepted =
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const TermsScreen()),
          ) ??
          false;

      // 「同意しない」の場合はここで終了（ログイン画面へは進ませない）
      if (!accepted) return;
      // ※ TermsScreen 側で TermsService.acceptCurrentTerms() を呼んでおく想定
    }

    // ③ ここまで来たら「規約OK」なので、いつものログイン判定に進む
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
              'image_dir/test1.jpg', // ← ここは好きな画像に差し替えてOK
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
