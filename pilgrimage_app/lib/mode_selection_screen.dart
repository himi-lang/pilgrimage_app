import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_route_observer.dart';
import 'app_routes.dart';
import 'image_search_screen.dart';
import 'map_screen.dart';
import 'service/app_audio_service.dart';
import 'widgets/app_ui.dart';

const String _defaultBackgroundImage = 'assets/image_dir/main_visual.jpg';
const String _mapModeBackgroundImage = 'assets/image_dir/long_hair.jpg';
const String _versusModeBackgroundImage = 'assets/image_dir/short_hair.jpg';
const String _versusSubModeBackgroundImage = 'assets/image_dir/background.jpg';

const List<String> _modeBackgroundImages = <String>[
  _defaultBackgroundImage,
  _mapModeBackgroundImage,
  _versusModeBackgroundImage,
  _versusSubModeBackgroundImage,
];

enum _MenuPage { top, map, versus }

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen>
    with RouteAware {
  Future<void>? _precacheFuture;
  _MenuPage _currentPage = _MenuPage.top;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    AppAudioService.instance.playMainBgm();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheFuture ??= _precacheBackgroundImages();

    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && _route != route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    AppAudioService.instance.playMainBgm();
  }

  @override
  void didPopNext() {
    AppAudioService.instance.playMainBgm();
  }

  Future<void> _precacheBackgroundImages() async {
    for (final imagePath in _modeBackgroundImages) {
      await precacheImage(AssetImage(imagePath), context);
    }
  }

  Future<void> _precacheOne(String imagePath) async {
    await precacheImage(AssetImage(imagePath), context);
  }

  String get _currentBackgroundPath {
    switch (_currentPage) {
      case _MenuPage.top:
        return _defaultBackgroundImage;
      case _MenuPage.map:
        return _mapModeBackgroundImage;
      case _MenuPage.versus:
        return _versusModeBackgroundImage;
    }
  }

  String get _currentTitle {
    switch (_currentPage) {
      case _MenuPage.top:
        return 'Anime Atlas';
      case _MenuPage.map:
        return '聖地マップモード';
      case _MenuPage.versus:
        return '対戦モード';
    }
  }

  bool get _showBackButton => _currentPage != _MenuPage.top;

  Future<void> _switchPage(_MenuPage nextPage) async {
    await (_precacheFuture ??= _precacheBackgroundImages());
    if (!mounted) return;

    setState(() {
      _currentPage = nextPage;
    });
  }

  void _handleBack() {
    if (_currentPage == _MenuPage.top) {
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {
      _currentPage = _MenuPage.top;
    });
  }

  Future<void> _pushAfterPrecaching({
    required String imagePath,
    required Widget page,
  }) async {
    await _precacheOne(imagePath);
    if (!mounted) return;

    await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => page));
  }

  Future<void> _pushNamedAfterBackgroundReady({
    required String routeName,
    required String imagePath,
  }) async {
    await _precacheOne(imagePath);
    if (!mounted) return;

    await Navigator.pushNamed(context, routeName);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        leading: _showBackButton ? AppBackButton(onPressed: _handleBack) : null,
        middle: Text(
          _currentTitle,
          style: const TextStyle(color: CupertinoColors.white),
        ),
        backgroundColor: cs.primary,
        automaticBackgroundVisibility: false,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_currentPage == _MenuPage.map)
              const ModeSwitchButton(currentMode: AppMode.map),
            AppMenuButton(),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: SizedBox.expand(
              key: ValueKey(_currentBackgroundPath),
              child: _AnimatedBackground(
                imagePath: _currentBackgroundPath,
                overlayAlpha: 0,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: RepaintBoundary(
                          child: KeyedSubtree(
                            key: ValueKey(_currentPage),
                            child: _buildPageBody(cs),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VisitedRecordShortcut(
            alignment: Alignment.topRight,
            minimumPadding: EdgeInsets.only(top: 16, right: 16),
            safeAreaTop: false,
            safeAreaBottom: false,
            safeAreaLeft: false,
          ),
        ],
      ),
    );
  }

  Widget _buildPageBody(ColorScheme cs) {
    switch (_currentPage) {
      case _MenuPage.top:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeMenuCard(
              icon: Icons.map,
              title: '聖地マップモード',
              subtitle: '地図で探す・作品から探す',
              backgroundColor: cs.surface,
              onTap: () => _switchPage(_MenuPage.map),
            ),

            const SizedBox(height: 16),

            _ModeMenuCard(
              icon: Icons.sports_esports,
              title: '対戦モード',
              subtitle: '早押しクイズ：みんなと / プライベート',
              backgroundColor: cs.surface,
              onTap: () => _switchPage(_MenuPage.versus),
            ),
          ],
        );

      case _MenuPage.map:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeMenuCard(
              icon: Icons.map_outlined,
              title: '地図から探す',
              subtitle: '地図からスポットを発見・検索',
              backgroundColor: cs.surfaceContainer,
              onTap: () {
                _pushAfterPrecaching(
                  imagePath: _mapModeBackgroundImage,
                  page: const MapScreen(),
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
                _pushAfterPrecaching(
                  imagePath: _defaultBackgroundImage,
                  page: const ImageSearchScreen(),
                );
              },
            ),
          ],
        );

      case _MenuPage.versus:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeMenuCard(
              icon: Icons.lock,
              title: 'プライベート対戦',
              subtitle: 'ひとりで遊ぶ・友達と遊ぶ',
              backgroundColor: cs.surfaceContainer,
              onTap: () {
                _pushNamedAfterBackgroundReady(
                  routeName: AppRoutes.versusLobby,
                  imagePath: _versusSubModeBackgroundImage,
                );
              },
            ),
            const SizedBox(height: 16),
            _ModeMenuCard(
              icon: Icons.group,
              title: 'みんなと対戦',
              subtitle: '全国のユーザーとランダムマッチ',
              backgroundColor: cs.surfaceContainer,
              onTap: () {
                _pushNamedAfterBackgroundReady(
                  routeName: AppRoutes.versusPublicWait,
                  imagePath: _versusSubModeBackgroundImage,
                );
              },
            ),
          ],
        );
    }
  }
}

class _AnimatedBackground extends StatelessWidget {
  final String imagePath;
  final double overlayAlpha;

  const _AnimatedBackground({required this.imagePath, this.overlayAlpha = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF1E456E)),
        Image.asset(imagePath, fit: BoxFit.cover, gaplessPlayback: true),
        ColoredBox(
          color: CupertinoColors.white.withValues(alpha: overlayAlpha),
        ),
      ],
    );
  }
}

//カードの中身を設定。
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: AppAudioService.instance.withTapSfx(onTap),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: backgroundColor,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: CupertinoColors.white),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: "keifont",
                        color: CupertinoColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_right,
                color: CupertinoColors.white,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
