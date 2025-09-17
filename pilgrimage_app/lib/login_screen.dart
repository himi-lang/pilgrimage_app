import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

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
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? '認証エラーが発生しました');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGoogle() async {
    setState(() => _busy = true);
    try {
      UserCredential uc;

      if (kIsWeb) {
        // Web は Firebase のポップアップでOK
        uc = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        // google_sign_in v7 仕様：instance + initialize() + authenticate()
        // 旧 signIn() 相当
        final googleUser = await GoogleSignIn().signIn();

        if (googleUser == null) {
          _toast('キャンセルしました');
          return;
        }

        final gAuth = await googleUser.authentication; // idToken が得られる
        final cred = GoogleAuthProvider.credential(idToken: gAuth.idToken);
        uc = await FirebaseAuth.instance.signInWithCredential(cred);
      }
      if (uc.user != null) _toast('Googleでサインインしました');
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Googleサインインに失敗しました');
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
