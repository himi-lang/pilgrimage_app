// lib/terms_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _termsAssetPath = 'information/Terms_of_use_first.txt';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('利用規約'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: rootBundle.loadString(_termsAssetPath),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
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
                  return Scrollbar(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop(false); // 同意しない
                      },
                      child: const Text('同意しない'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(true); // 同意する
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
