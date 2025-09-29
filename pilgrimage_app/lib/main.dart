// main.dart — Firebase初期化の例外吸収 + 認証ゲート + ルート整理（プレースホルダー付き）
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'versus/versus_lobby_screen.dart';
import 'versus/versus_room_screen.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'mode_selection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    // e.g. 未対応プラットフォームや options 未生成時
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
      title: '聖地巡礼マップ',
      theme: ThemeData(
        useMaterial3: false,
        colorSchemeSeed: const Color.fromARGB(255, 79, 255, 249), //全体のカラーを変更
      ),
      home: const _AuthGate(),
      routes: {
        '/map': (_) => const MapScreen(),
        '/versus/lobby': (_) => const VersusLobbyScreen(), // ← 本物へ
      },
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/versus/room/')) {
          final id = name.substring('/versus/room/'.length);
          return MaterialPageRoute(
            builder: (_) => VersusRoomScreen(roomId: id), // ← 本物へ
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data != null
            ? const ModeSelectionScreen()
            : const LoginScreen();
      },
    );
  }
}
/*
// ==== 以下、未実装画面のプレースホルダー（存在しない import でビルドが落ちるのを防ぐ）====
class VersusLobbyScreen extends StatelessWidget {
  const VersusLobbyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('対戦ロビー（準備中）')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('この画面は仮のプレースホルダーです。'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/map'),
              child: const Text('聖地マップへ'),
            ),
          ],
        ),
      ),
    );
  }
}
*/

/*class VersusRoomScreen extends StatelessWidget {ここは、メンテなどで対戦が使えない時に使う画面。
  final String roomId;
  const VersusRoomScreen({super.key, required this.roomId});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('対戦ルーム $roomId（準備中）')),
      body: const Center(child: Text('対戦機能は現在準備中です。')),
    );
  }
}
*/
