// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'versus/versus_lobby_screen.dart';
import 'versus/versus_room_screen.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'mode_selection_screen.dart';
import 'start_screen.dart'; // ★ 追加：タップしてスタート画面

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    await Firebase.initializeApp();
  }
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

      // ★ ここを _AuthGate から StartScreen に変更
      home: const StartScreen(),

      // ルート整理（必要に応じて追加）
      routes: {
        '/login': (_) => const LoginScreen(),
        '/mode_selection': (_) => const ModeSelectionScreen(),
        '/map': (_) => const MapScreen(),
        '/versus/lobby': (_) => const VersusLobbyScreen(),
      },

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
