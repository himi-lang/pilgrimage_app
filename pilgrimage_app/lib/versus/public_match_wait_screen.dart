import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../widgets/app_ui.dart';
import '../widgets/dialogs.dart';
import 'versus_service.dart';

class PublicMatchWaitScreen extends StatefulWidget {
  const PublicMatchWaitScreen({super.key});

  @override
  State<PublicMatchWaitScreen> createState() => _PublicMatchWaitScreenState();
}

class _PublicMatchWaitScreenState extends State<PublicMatchWaitScreen>
    with SingleTickerProviderStateMixin {
  final _service = VersusService();
  final _db = FirebaseFirestore.instance;
  bool _loading = false;
  String? _roomId;
  String? _matchingHint;
  bool _quoteLoading = true;
  String _animeTitle = '読み込み中...';
  String _animeQuote = '';
  int _dotCount = 1;
  bool _showBack = false;
  Timer? _dotTimer;
  late final AnimationController _flipController;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _startDotAnimation();
    _loadRandomQuote();
    _startMatching();
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _flipController.dispose();
    super.dispose();
  }

  void _startDotAnimation() {
    _dotTimer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount % 3) + 1);
    });
  }

  Future<void> _loadRandomQuote() async {
    Map<String, String>? picked;
    try {
      picked = await _pickFromQuoteCollection();
      picked ??= await _pickFromWorksCollection();
    } catch (e) {
      debugPrint('[PublicMatchWait] quote load error: $e');
    }

    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _animeTitle = picked!['title']!;
        _animeQuote = picked['quote']!;
        _quoteLoading = false;
      });
      return;
    }

    setState(() {
      _animeTitle = '名言準備中';
      _animeQuote = 'この作品の名言は後で追加されます。';
      _quoteLoading = false;
    });
  }

  Future<Map<String, String>?> _pickFromQuoteCollection() async {
    try {
      final snap = await _db.collection('アニメ名言集').get();
      final docs =
          snap.docs.where((d) {
            final data = d.data();
            final desc =
                (data['description'] ?? data['quote'] ?? '').toString().trim();
            return desc.isNotEmpty;
          }).toList();
      if (docs.isEmpty) return null;
      final pick = docs[Random().nextInt(docs.length)];
      final data = pick.data();
      final quote =
          (data['description'] ?? data['quote'] ?? '').toString().trim();
      return {'title': pick.id, 'quote': quote};
    } catch (e) {
      debugPrint('[PublicMatchWait] アニメ名言集 read failed: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _pickFromWorksCollection() async {
    try {
      final snap = await _db.collection('作品一覧フライヤー').get();
      if (snap.docs.isEmpty) return null;
      final pick = snap.docs[Random().nextInt(snap.docs.length)];
      final data = pick.data();
      final quote =
          (data['description'] ?? data['note'] ?? '名言は準備中です').toString().trim();
      return {'title': pick.id, 'quote': quote};
    } catch (e) {
      debugPrint('[PublicMatchWait] 作品一覧フライヤー read failed: $e');
      return null;
    }
  }

  Future<void> _startMatching() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final roomId = await _service.quickJoin();
      if (!mounted) return;
      setState(() {
        _roomId = roomId;
        _matchingHint = null;
        _loading = false;
      });
      Navigator.of(context).pushReplacementNamed(AppRoutes.versusRoom(roomId));
    } catch (e) {
      debugPrint('[PublicMatchWait] matching failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessageDialog(context, 'マッチングに失敗しました');
    }
  }

  Future<void> _cancelMatch() async {
    final roomId = _roomId;
    if (roomId != null) {
      await _service.leaveRoom(roomId);
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.modeSelection, (r) => false);
  }

  Future<void> _toggleCard() async {
    if (_flipController.isAnimating || _quoteLoading) return;
    if (_showBack) {
      await _flipController.reverse();
      if (mounted) setState(() => _showBack = false);
    } else {
      await _flipController.forward();
      if (mounted) setState(() => _showBack = true);
    }
  }

  Widget _buildFlipCard() {
    final faceText =
        _showBack
            ? _animeTitle
            : (_animeQuote.isEmpty ? '名言が登録されていません。' : _animeQuote);
    return GestureDetector(
      onTap: _toggleCard,
      child: AnimatedBuilder(
        animation: _flipController,
        builder: (context, child) {
          final angle = _flipController.value * pi;
          final isBack = angle > pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform:
                Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(angle),
            child:
                isBack
                    ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(pi),
                      child: child,
                    )
                    : child,
          );
        },
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360, minHeight: 220),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CupertinoColors.systemGrey3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child:
                _quoteLoading
                    ? const CupertinoActivityIndicator()
                    : Text(
                      faceText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _cancelMatch();
      },
      child: CupertinoPageScaffold(
        navigationBar: commonAppBar(
          context,
          title: '対戦待機',
          currentMode: AppMode.versus,
        ),
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'みんなで対戦',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  _buildFlipCard(),
                  const SizedBox(height: 24),
                  Text(
                    'マッチング中${'.' * _dotCount}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_matchingHint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _matchingHint!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  CupertinoButton.filled(
                    onPressed: _cancelMatch,
                    child: const Text('キャンセル'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
