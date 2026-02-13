// lib/terms_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'service/terms_service.dart'; // ★ 追加（パスはこのファイルからの相対）

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _termsAssetPath = 'assets/information/Terms_of_use_first.txt';

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('利用規約'),
        automaticallyImplyLeading: false,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 規約本文
            Expanded(
              child: FutureBuilder<String>(
                future: rootBundle.loadString(_termsAssetPath),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '内容の読み込みに失敗しました。\n\n${snapshot.error}',
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    );
                  }
                  final text = snapshot.data ?? '';
                  return CupertinoScrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        text,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 0),

            // ボタン行
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // 同意しない
                  Expanded(
                    child: CupertinoButton(
                      onPressed: () {
                        // 呼び出し元に false を返して閉じる
                        Navigator.of(context).pop(false);
                      },
                      color: CupertinoColors.systemGrey4,
                      child: const Text(
                        '同意しない',
                        style: TextStyle(color: CupertinoColors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 同意する
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: () async {
                        // フラグ保存
                        await TermsService.acceptCurrentTerms();
                        // 呼び出し元に true を返して閉じる
                        Navigator.of(context).pop(true);
                      },
                      child: const Text('同意する'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
