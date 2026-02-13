import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'mode_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder:
          (_) => CupertinoAlertDialog(
            content: Text(msg),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _handleEmail() async {
    if (_email.text.trim().isEmpty || _pass.text.length < 6) {
      _toast('メールと6文字以上のパスワードを入力してください');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isSignUp) {
        final uc = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text,
        );
        final displayName = _name.text.trim();
        if (displayName.isNotEmpty) {
          await uc.user?.updateDisplayName(displayName);
        }
        _toast('登録しました');
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text,
        );
        _toast('ログインしました');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(builder: (_) => const ModeSelectionScreen()),
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? '認証エラーが発生しました');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Google ログイン（google_sign_in パッケージは使わず FirebaseAuth 経由にする）
  Future<void> _handleGoogle() async {
    setState(() => _busy = true);

    try {
      if (kIsWeb) {
        // Web のときは Popup で認証
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // ---- モバイル(Android/iOS) ----
        // v7 では initialize → authenticate の流れ
        await GoogleSignIn.instance.initialize();

        final googleUser = await GoogleSignIn.instance.authenticate();
        final googleAuth = googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.idToken,
          idToken: googleAuth.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (!mounted) return;

      _toast('ログインしました');
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(builder: (_) => const ModeSelectionScreen()),
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Googleサインインでエラーが発生しました');
    } catch (e) {
      _toast('Googleサインインでエラーが発生しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSignUp ? '新規登録' : 'ログイン';
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('メールアドレス'),
                  const SizedBox(height: 6),
                  CupertinoTextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    placeholder: 'example@example.com',
                    enabled: !_busy,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  const Text('パスワード（6文字以上）'),
                  const SizedBox(height: 6),
                  CupertinoTextField(
                    controller: _pass,
                    obscureText: _obscure,
                    enabled: !_busy,
                    autocorrect: false,
                    suffix: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 30,
                      onPressed: () => setState(() => _obscure = !_obscure),
                      child: Icon(
                        _obscure
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: 20,
                      ),
                    ),
                  ),
                  if (_isSignUp) ...[
                    const SizedBox(height: 12),
                    const Text('表示名（任意）'),
                    const SizedBox(height: 6),
                    CupertinoTextField(
                      controller: _name,
                      enabled: !_busy,
                      autocorrect: false,
                    ),
                  ],
                  const SizedBox(height: 16),
                  CupertinoButton.filled(
                    onPressed: _busy ? null : _handleEmail,
                    child: Text(title),
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    onPressed: _busy ? null : _handleGoogle,
                    child: const Text('Googleで続ける'),
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    onPressed:
                        _busy
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp
                          ? '既にアカウントをお持ちの方（ログインへ）'
                          : 'アカウントをお持ちでない方（新規登録へ）',
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CupertinoActivityIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
