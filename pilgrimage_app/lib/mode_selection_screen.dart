import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'start_screen.dart';
import 'widgets/app_ui.dart';
import 'terms_screen.dart'; // このファイルは次のセクションで作る

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen> {
  static const _termsKey = 'terms_accepted_v1';

  @override
  void initState() {
    super.initState();
    // build が一度終わってから規約チェック
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTermsAccepted();
    });
  }

  Future<void> _ensureTermsAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    final agreed = prefs.getBool(_termsKey) ?? false;
    if (agreed) return;

    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TermsScreen()));

    if (!mounted) return;

    if (result == true) {
      // 同意した → フラグ保存
      await prefs.setBool(_termsKey, true);
    } else {
      // 同意しない → ログアウトしてスタート画面へ
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const StartScreen()),
        (route) => false,
      );
    }
  }

  // もともとの card ウィジェットは State クラスのメソッドにする
  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cs.surfaceContainer,
        ),
        child: Row(
          children: [
            Icon(icon, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: commonAppBar(context, title: 'モード選択'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _card(
              icon: Icons.map,
              title: '聖地マップモード',
              subtitle: '地図で巡礼・検索・お気に入り',
              onTap: () => Navigator.pushReplacementNamed(context, '/map'),
            ),
            const SizedBox(height: 16),
            _card(
              icon: Icons.sports_esports,
              title: '対戦モード',
              subtitle: '早押しクイズ：公開/プライベート',
              onTap:
                  () =>
                      Navigator.pushReplacementNamed(context, '/versus/lobby'),
            ),
          ],
        ),
      ),
    );
  }
}
