// lib/mode_selection_screen.dart
import 'package:flutter/material.dart';
import 'widgets/app_ui.dart';
import 'map_screen.dart';
import 'image_search_screen.dart';
import 'widgets/bottom_banner_ad.dart';
import 'ads/interstitial_ad_manager.dart';

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget card({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
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

    return Scaffold(
      appBar: commonAppBar(context, title: 'モード選択'),
      body: Column(
        children: [
          // 上側：今までのカードリスト
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // ★ マップモード → 専用メニュー画面へ
                  card(
                    icon: Icons.map,
                    title: '聖地マップモード',
                    subtitle: '地図で巡礼・検索・お気に入り',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MapModeMenuScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // 対戦モード（今まで通り）
                  card(
                    icon: Icons.sports_esports,
                    title: '対戦モード',
                    subtitle: '早押しクイズ：公開/プライベート',
                    onTap: () {
                      InterstitialAdManager.show(
                        onFinished: () {
                          Navigator.pushReplacementNamed(
                            context,
                            '/versus/lobby',
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 下側：バナー広告
          const BottomBannerAd(),
        ],
      ),
    );
  }
}

/// マップモード内のサブメニュー
/// 「マップ検索モード」「画像検索モード」を選ぶ画面
class MapModeMenuScreen extends StatelessWidget {
  const MapModeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget card({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
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

    return Scaffold(
      // 上の「モード選択へ」ボタンは commonAppBar の ModeSwitchButton がやってくれる
      appBar: commonAppBar(context, title: 'マップモード', currentMode: AppMode.map),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // ① これまで通りの地図画面
                  card(
                    icon: Icons.map_outlined,
                    title: 'マップ検索モード',
                    subtitle: '地図を見ながらスポットを探す',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MapScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // ② 作品ごとの画像から選ぶ画面
                  card(
                    icon: Icons.image_search,
                    title: '画像検索モード',
                    subtitle: '作品画像から聖地を選ぶ',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ImageSearchScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const BottomBannerAd(),
        ],
      ),
    );
  }
}
