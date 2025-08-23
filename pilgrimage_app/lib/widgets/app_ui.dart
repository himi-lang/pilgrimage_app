import 'package:flutter/material.dart';
import '../service/auth_service.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'ログアウト',
      onPressed: () => AuthService.signOutAndGoRoot(context),
      icon: const Icon(Icons.logout),
    );
  }
}

enum AppMode { map, versus }

class ModeSwitchButton extends StatelessWidget {
  final AppMode currentMode;
  // ルーム等で離脱確認を出したい時に使う（trueで遷移続行）
  final Future<bool> Function()? confirm;
  // 遷移前処理（退室APIなど）
  final Future<void> Function()? beforeNavigate;

  const ModeSwitchButton({
    super.key,
    required this.currentMode,
    this.confirm,
    this.beforeNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final toMap = currentMode != AppMode.map;
    return IconButton(
      tooltip: toMap ? '聖地マップへ' : '対戦ロビーへ',
      icon: Icon(toMap ? Icons.map : Icons.sports_esports),
      onPressed: () async {
        if (confirm != null) {
          final ok = await confirm!();
          if (!ok) return;
        }
        if (beforeNavigate != null) {
          await beforeNavigate!();
        }
        final dest = toMap ? '/map' : '/versus/lobby';
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed(dest);
        }
      },
    );
  }
}

/// 共通AppBar（右端：モード切替 → 追加actions → ログアウト）
PreferredSizeWidget commonAppBar(
  BuildContext context, {
  required String title,
  List<Widget> actionsExtra = const [],
  AppMode? currentMode,
  Future<bool> Function()? modeConfirm,
  Future<void> Function()? modeBeforeNavigate,
}) {
  return AppBar(
    title: Text(title),
    actions: [
      if (currentMode != null)
        ModeSwitchButton(
          currentMode: currentMode,
          confirm: modeConfirm,
          beforeNavigate: modeBeforeNavigate,
        ),
      ...actionsExtra,
      const LogoutButton(),
    ],
  );
}
