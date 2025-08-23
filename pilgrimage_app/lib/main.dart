// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'login_screen.dart';
import 'map_screen.dart';

// ★ 新規画面のimport
import 'mode_selection_screen.dart';
import 'versus/versus_lobby_screen.dart';
import 'versus/versus_room_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //デバッグ用
  debugPrint('projectId = ${Firebase.app().options.projectId}');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '聖地巡礼マップ',
      initialRoute: '/',
      onGenerateRoute: (settings) {
        // /versus/room/:id を受ける
        if (settings.name != null &&
            settings.name!.startsWith('/versus/room/')) {
          final id = settings.name!.split('/').last;
          return MaterialPageRoute(
            builder: (_) => VersusRoomScreen(roomId: id),
          );
        }
        return null; // 下のroutesへフォールバック
      },
      routes: {
        // ★ ここを LoginScreen ではなく「認証ゲート」にする
        '/': (_) => const _AuthGate(),
        '/mode': (_) => const ModeSelectionScreen(),
        '/map': (_) => const MapScreen(),
        '/versus/lobby': (_) => const VersusLobbyScreen(),
      },
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    );
  }
}

// ★ ログイン状態で出し分ける薄いゲート（Navigator不要）
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
