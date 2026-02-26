// lib/mode_selection_screen.dart
import 'package:flutter/cupertino.dart';
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

    Widget card //のちのち使うcardっていうwidgetのひな形を作成。
    ({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return InkWell //widgetで、タップできるように。タップ時のリップルも出してくれる。
      (
        onTap: onTap, //インスタンスを作成するときに指定する。
        child: Container(
          //タッチできる箱を作る。
          padding: const EdgeInsets.all(20), //paddingを左右上下に20px
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surface,
          ),
          child: Row //横向きにwidgetを配置していく。
          (
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
                      style: TextStyle(color: CupertinoColors.white),
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
      child: Material(
        color: Colors.white,
        child: Column(
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
                    card(
                      icon: Icons.sports_esports,
                      title: '対戦モード',
                      subtitle: '早押しクイズ：みんなと / プライベート',
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
            const BottomBannerAd(),
          ],
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

    Widget card //表示するボタンの中身をここで設定する。のちにこれに入れてボタンを作成する。
    ({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20), //左右上下に20pxのpaddingを用意
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surfaceContainer,
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
                      style: TextStyle(color: CupertinoColors.white),
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
      child: Material //ここからappBarから下の箱
      (
        color: Colors.transparent,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView //スクロール可能なバー
                (
                  children: [
                    card(
                      icon: Icons.map_outlined,
                      title: '地図から探す',
                      subtitle: '地図からスポットを発見・検索',
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(builder: (_) => const MapScreen()),
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
            const BottomBannerAd(),
          ],
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

    Widget card({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,

        child: Container //装飾可能で押せる箱を作成する。
        (
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surfaceContainer,
          ),

          child: Row //横軸に子供を並べる。
          (
            children: //複数の子を並べられる。
                [
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
                      style: TextStyle(color: CupertinoColors.white),
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
      child: Material(
        color: Colors.transparent,
        child: Column(
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
            const BottomBannerAd(),
          ],
        ),
      ),
    );
  }
}
