import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        MaterialPageRoute(builder: (_) => const ModeSelectionScreen()),
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
        if (googleUser == null) {
          _toast('キャンセルされました');
          return;
        }

        final googleAuth = await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.idToken,
          idToken: googleAuth.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (!mounted) return;

      _toast('ログインしました');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ModeSelectionScreen()),
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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'メールアドレス'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'パスワード（6文字以上）',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (_isSignUp) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: '表示名（任意）'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _handleEmail,
                    child: Text(title),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _handleGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text('Googleで続ける'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
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
                    const Center(child: CircularProgressIndicator()),
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
