// lib/mode_selection_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'widgets/app_ui.dart';
import 'map_screen.dart';
import 'image_search_screen.dart';
import 'widgets/bottom_banner_ad.dart';
import 'ads/interstitial_ad_manager.dart';

Widget withTestBackground(Widget child, {double overlayAlpha = 0.82}) {
  return Container(
    decoration: const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/image_dir/long_hair.jpg'),
        fit: BoxFit.cover,
      ),
    ),
    child: Container(
      color: Colors.white.withValues(alpha: overlayAlpha),
      child: child,
    ),
  );
}

class _ModeMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color backgroundColor;

  const _ModeMenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: backgroundColor,
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: CupertinoColors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: CupertinoColors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: CupertinoColors.white),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              color: CupertinoColors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    //ここから画面の形を作っていく。widget buildに返す。
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        middle: Text(
          'Anime Atlas',
          style: TextStyle(color: CupertinoColors.white),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        automaticBackgroundVisibility: false,
        trailing: AppMenuButton(),
      ),
      child: withTestBackground(
        Material(
          color: Colors.transparent,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ★ 聖地マップモード → マップ用サブメニュー
                        _ModeMenuCard(
                          icon: Icons.map,
                          title: '聖地マップモード',
                          subtitle: '地図で探す・作品から探す',
                          backgroundColor: cs.surface,
                          onTap: () {
                            //on_clickedと同じ
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => const MapModeMenuScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // ★ 対戦モード → 対戦モード用サブメニュー
                        _ModeMenuCard(
                          icon: Icons.sports_esports,
                          title: '対戦モード',
                          subtitle: '早押しクイズ：みんなと / プライベート',
                          backgroundColor: cs.surface,
                          onTap: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => const VersusModeMenuScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const BottomBannerAd(),
          ],
        ),
      ),
      ),
    );
  }
}

/// マップモード内のサブメニュー
class MapModeMenuScreen extends StatelessWidget {
  //聖地マップモード選択画面
  const MapModeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CupertinoPageScaffold //聖地マップモードの選択画面の本体。
    (
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        leading:
            const AppBackButton(), //純正の戻るボタンに白色つけたらバグがあった。詳細はapp=ui.dartに記載されている。
        middle: const Text(
          '聖地マップモード',
          style: TextStyle(color: CupertinoColors.white),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        automaticBackgroundVisibility: false,
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModeSwitchButton(currentMode: AppMode.map),
            AppMenuButton(),
          ],
        ),
      ),
      child: withTestBackground(
        Material //ここからappBarから下の箱
        (
          color: Colors.transparent,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ModeMenuCard(
                          icon: Icons.map_outlined,
                          title: '地図から探す',
                          subtitle: '地図からスポットを発見・検索',
                          backgroundColor: cs.surfaceContainer,
                          onTap: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(builder: (_) => const MapScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _ModeMenuCard(
                          icon: Icons.image_search,
                          title: '作品から探す',
                          subtitle: 'アニメ作品を検索・タップ',
                          backgroundColor: cs.surfaceContainer,
                          onTap: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => const ImageSearchScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const BottomBannerAd(),
          ],
        ),
      ),
      ),
    );
  }
}

/// 対戦モード内のサブメニュー
/// ボタン1: プライベート対戦
/// ボタン2: みんなと対戦
class VersusModeMenuScreen extends StatelessWidget {
  //対戦モードの画面を作成している。
  const VersusModeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CupertinoPageScaffold(
      navigationBar: commonAppBar(
        context,
        title: '対戦モード',
        leading: AppBackButton(
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            nav.pushNamedAndRemoveUntil('/mode_selection', (route) => false);
          },
        ),
        // AppMode に versus があれば渡してもOK
        // currentMode: AppMode.versus,
      ),
      child: withTestBackground(
        Material(
          color: Colors.transparent,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ボタン1：プライベート対戦
                        _ModeMenuCard(
                          icon: Icons.lock,
                          title: 'プライベート対戦',
                          subtitle: 'ひとりで遊ぶ・友達と遊ぶ',
                          backgroundColor: cs.surfaceContainer,
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
                        _ModeMenuCard(
                          icon: Icons.group,
                          title: 'みんなと対戦',
                          subtitle: '全国のユーザーとランダムマッチ',
                          backgroundColor: cs.surfaceContainer,
                          onTap: () {
                            InterstitialAdManager.show(
                              onFinished: () {
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/versus/public_wait',
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const BottomBannerAd(),
          ],
        ),
      ),
      ),
    );
  }
}
