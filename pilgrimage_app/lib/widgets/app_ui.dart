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

/// どの画面でも使える共通AppBar
PreferredSizeWidget commonAppBar(
  BuildContext context, {
  required String title,
  List<Widget> actionsExtra = const [],
}) {
  return AppBar(
    title: Text(title),
    actions: [...actionsExtra, const LogoutButton()],
  );
}
