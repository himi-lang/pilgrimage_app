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
      appBar: commonAppBar(context, title: 'Anime Atlas'),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // ★ 聖地マップモード → マップ用サブメニュー
                  card(
                    icon: Icons.map,
                    title: '聖地マップモード',
                    subtitle: '地図で探す・作品から探す',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MapModeMenuScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // ★ 対戦モード → 対戦モード用サブメニュー
                  card(
                    icon: Icons.sports_esports,
                    title: '対戦モード',
                    subtitle: '早押しクイズ：みんなと / プライベート',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const VersusModeMenuScreen(),
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

/// マップモード内のサブメニュー
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
      appBar: commonAppBar(
        context,
        title: '聖地マップモード',
        currentMode: AppMode.map,
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  card(
                    icon: Icons.map_outlined,
                    title: '地図から探す',
                    subtitle: '地図からスポットを発見・検索',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MapScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  card(
                    icon: Icons.image_search,
                    title: '作品から探す',
                    subtitle: 'アニメ作品を検索・タップ',
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

/// 対戦モード内のサブメニュー
/// ボタン1: プライベート対戦
/// ボタン2: みんなと対戦
class VersusModeMenuScreen extends StatelessWidget {
  const VersusModeMenuScreen({super.key});

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
      appBar: commonAppBar(
        context,
        title: '対戦モード',
        // AppMode に versus があれば渡してもOK
        // currentMode: AppMode.versus,
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // ボタン1：プライベート対戦
                  card(
                    icon: Icons.lock,
                    title: 'プライベート対戦',
                    subtitle: 'ひとりで遊ぶ・友達と遊ぶ',
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
                  const SizedBox(height: 16),
                  // ボタン2：みんなと対戦
                  card(
                    icon: Icons.group,
                    title: 'みんなと対戦',
                    subtitle: '全国のユーザーとランダムマッチ',
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
          const BottomBannerAd(),
        ],
      ),
    );
  }
}
