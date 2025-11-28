import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'firebase_options.dart';
import 'start_screen.dart';
import 'login_screen.dart';
import 'mode_selection_screen.dart';
import 'map_screen.dart';
import 'versus/versus_lobby_screen.dart';
import 'versus/versus_room_screen.dart';
import 'ads/interstitial_ad_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ★ AdMob/テスト広告の初期化
  await MobileAds.instance.initialize();

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
        useMaterial3: false,
        colorSchemeSeed: const Color.fromARGB(255, 62, 143, 255),
      ),

      // 最初の画面は今までどおり StartScreen
      home: const StartScreen(),

      // いままで使ってたルートたち
      routes: {
        '/login': (_) => const LoginScreen(),
        '/mode_selection': (_) => const ModeSelectionScreen(),
        '/map': (_) => const MapScreen(),
        '/versus/lobby': (_) => const VersusLobbyScreen(),
      },

      // /versus/room/{roomId} だけ特別扱い
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/versus/room/')) {
          final id = name.substring('/versus/room/'.length);
          return MaterialPageRoute(
            builder: (_) => VersusRoomScreen(roomId: id),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
