import 'package:flutter/cupertino.dart';

Future<void> showAppMessageDialog(
  BuildContext context,
  String message, {
  String okLabel = 'OK',
}) {
  return showCupertinoDialog<void>(
    context: context,
    builder:
        (dialogContext) => CupertinoAlertDialog(
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(okLabel),
            ),
          ],
        ),
  );
}
