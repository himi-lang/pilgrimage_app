import 'package:flutter/material.dart';
import 'widgets/app_ui.dart';

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget card({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surfaceContainer,
          ),
          child: Row(
            children: [
              Icon(icon, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: commonAppBar(context, title: 'モード選択'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            card(
              icon: Icons.map,
              title: '聖地マップモード',
              subtitle: '地図で巡礼・検索・お気に入り',
              onTap: () => Navigator.pushReplacementNamed(context, '/map'),
            ),
            const SizedBox(height: 16),
            card(
              icon: Icons.sports_esports,
              title: '対戦モード',
              subtitle: '早押しクイズ：公開/プライベート',
              onTap:
                  () =>
                      Navigator.pushReplacementNamed(context, '/versus/lobby'),
            ),
          ],
        ),
      ),
    );
  }
}
