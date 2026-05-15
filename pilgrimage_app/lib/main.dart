import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'start_screen.dart';
import 'login_screen.dart';
import 'mode_selection_screen.dart';
import 'map_screen.dart';
import 'visited_pilgrimage_screen.dart';
import 'app_route_observer.dart';
import 'app_routes.dart';
import 'service/app_audio_service.dart';
import 'versus/versus_lobby_screen.dart';
import 'versus/public_match_wait_screen.dart';
import 'versus/versus_room_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 画像キャッシュを抑えてメモリ圧迫を回避
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB
  //firebaseのデータを先に用意するため。
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await AppAudioService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Anime Atlas',
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            boldText: false,
            textScaler: const TextScaler.linear(1.0), //文字のサイズを固定
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        platform: TargetPlatform.iOS,
        useMaterial3: false,
        colorScheme: const ColorScheme.light(
          primary: Color.fromARGB(255, 30, 69, 110),
          secondary: CupertinoColors.activeGreen,
          surface: Color.fromARGB(255, 30, 69, 110),
          onSurface: CupertinoColors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F6F2),
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
          primaryColor: CupertinoColors.systemBlue,
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
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.modeSelection: (_) => const ModeSelectionScreen(),
        AppRoutes.map: (_) => const MapScreen(),
        AppRoutes.visitedSpots: (_) => const VisitedPilgrimageScreen(),
        AppRoutes.versusLobby: (_) => const VersusLobbyScreen(),
        AppRoutes.versusPublicWait: (_) => const PublicMatchWaitScreen(),
      },

      // /versus/room/{roomId} だけ特別扱い
      //対戦roomは毎回番号が違うので可変する。
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith(AppRoutes.versusRoomPrefix)) {
          final id = name.substring(AppRoutes.versusRoomPrefix.length);
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
