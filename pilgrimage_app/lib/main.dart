import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'firebase_options.dart';
import 'start_screen.dart';
import 'login_screen.dart';
import 'mode_selection_screen.dart';
import 'map_screen.dart';
import 'versus/versus_lobby_screen.dart';
import 'versus/public_match_wait_screen.dart';
import 'versus/versus_room_screen.dart';
import 'ads/interstitial_ad_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 画像キャッシュを抑えてメモリ圧迫を回避
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB
  //firebaseのデータを先に用意するため。
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ★ AdMob/テスト広告の初期化
  //AdMobを先に準備する。
  await MobileAds.instance.initialize();
  //インティスティシャル広告の先準備
  await InterstitialAdManager.preload();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Anime Atlas',
      theme: ThemeData(
        platform: TargetPlatform.iOS,
        useMaterial3: false,
        colorScheme: const ColorScheme.light(
          primary: CupertinoColors.activeBlue,
          secondary: CupertinoColors.activeGreen,
          surface: CupertinoColors.systemBackground,
          onSurface: CupertinoColors.black,
        ),
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: CupertinoColors.black,
              displayColor: CupertinoColors.black,
              decoration: TextDecoration.none,
              decorationColor: CupertinoColors.transparent,
            ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          },
        ),
        cupertinoOverrideTheme: const CupertinoThemeData(
          primaryColor: CupertinoColors.activeBlue,
          scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
          barBackgroundColor: CupertinoColors.systemGrey6,
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(
              color: CupertinoColors.black,
              decoration: TextDecoration.none,
              decorationColor: CupertinoColors.transparent,
            ),
            navTitleTextStyle: TextStyle(color: CupertinoColors.black),
            navLargeTitleTextStyle: TextStyle(color: CupertinoColors.black),
            navActionTextStyle: TextStyle(color: CupertinoColors.black),
          ),
        ),
      ),

      // 最初の画面は今までどおり StartScreen
      home: const StartScreen(),

      // いままで使ってたルートたち
      routes: {
        '/login': (_) => const LoginScreen(),
        '/mode_selection': (_) => const ModeSelectionScreen(),
        '/map': (_) => const MapScreen(),
        '/versus/lobby': (_) => const VersusLobbyScreen(),
        '/versus/public_wait': (_) => const PublicMatchWaitScreen(),
      },

      // /versus/room/{roomId} だけ特別扱い
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/versus/room/')) {
          final id = name.substring('/versus/room/'.length);
          return CupertinoPageRoute(
            builder: (_) => VersusRoomScreen(roomId: id),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
