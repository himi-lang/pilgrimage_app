import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import '../widgets/dialogs.dart';
import '../app_routes.dart';
import 'versus_service.dart';

const String _versusBackgroundImagePath = 'assets/image_dir/background.jpg';

class VersusLobbyScreen extends StatefulWidget {
  const VersusLobbyScreen({super.key});
  @override
  State<VersusLobbyScreen> createState() => _VersusLobbyScreenState();
}

class _VersusLobbyScreenState extends State<VersusLobbyScreen> {
  final s = VersusService();
  final codeCtrl = TextEditingController();
  bool _busy = false;
  Future<void>? _precacheFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheFuture ??= precacheImage(
      const AssetImage(_versusBackgroundImagePath),
      context,
    );
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    showAppMessageDialog(context, msg);
  }

  void _handleBackToVersusSelection() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil(
      AppRoutes.modeSelection,
      (route) => false,
    );
  }

  Future<void> _quickMatch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await s.quickJoin();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.versusRoom(id));
    } catch (e) {
      _toast('クイックマッチに失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createPrivate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await s.createRoom(isPrivate: true);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.versusRoom(id));
    } catch (e) {
      _toast('部屋の作成に失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinByCode() async {
    if (_busy) return;
    final raw = codeCtrl.text.trim().toUpperCase();
    if (raw.length != 6) {
      _toast('招待コードは6桁です');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await s.joinByCode(raw);
      if (id == null) {
        _toast('見つかりませんでした（コード・開始済み・終了の可能性）');
      } else {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.versusRoom(id));
      }
    } catch (e) {
      _toast('参加に失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    const fieldStyle = TextStyle(fontSize: 16, color: Colors.black);
    const placeholderStyle = TextStyle(
      fontSize: 15,
      color: CupertinoColors.systemGrey,
    );

    return CupertinoPageScaffold(
      navigationBar: commonAppBar(
        context,
        title: '対戦ロビー',
        currentMode: AppMode.versus,
        leading: AppBackButton(onPressed: _handleBackToVersusSelection),
      ),
      child: Container(
        // ★ 背景画像
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_versusBackgroundImagePath),
            fit: BoxFit.cover,
          ),
        ),
        // 背景の上にうっすら白をかぶせて内容を載せる
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white.withValues(alpha: 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CupertinoButton.filled(
                onPressed: _busy ? null : _quickMatch,
                child: Text(_busy ? '接続中…' : 'クイックマッチ'),
              ),
              const Divider(height: 32),
              Text('プライベートマッチ', style: titleStyle),
              const SizedBox(height: 8),
              CupertinoButton(
                onPressed: _busy ? null : _createPrivate,
                color: CupertinoColors.systemGrey5,
                child: const Text('部屋を作る'),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: CupertinoTextField(
                        controller: codeCtrl,
                        style: fieldStyle,
                        placeholderStyle: placeholderStyle,
                        maxLines: 1,
                        textCapitalization: TextCapitalization.characters,
                        placeholder: '招待コード6桁',
                        autocorrect: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(44, 44),
                    onPressed: _busy ? null : _joinByCode,
                    child: const Text('参加'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
