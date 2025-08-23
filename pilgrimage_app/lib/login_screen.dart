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
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text,
        );
        final display = _name.text.trim();
        if (display.isNotEmpty) {
          await cred.user?.updateDisplayName(display);
        }
        _toast('登録しました');
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text,
        );
        _toast('ログインしました');
      }
      // 画面遷移は main.dart の _AuthGate に任せる
    } on FirebaseAuthException catch (e) {
      _toast(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGoogle() async {
    setState(() => _busy = true);
    try {
      UserCredential uc;
      if (kIsWeb) {
        uc = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        final gUser = await GoogleSignIn().signIn();
        if (gUser == null) return; // キャンセル
        final gAuth = await gUser.authentication;
        final cred = GoogleAuthProvider.credential(
          idToken: gAuth.idToken,
          accessToken: gAuth.accessToken,
        );
        uc = await FirebaseAuth.instance.signInWithCredential(cred);
      }

      final isNew = uc.additionalUserInfo?.isNewUser ?? false;

      // （任意）初回だけ Firestore にユーザープロファイル作成
      // import 'package:cloud_firestore/cloud_firestore.dart'; が必要
      // await FirebaseFirestore.instance.collection('users')
      //   .doc(uc.user!.uid)
      //   .set({
      //     'displayName': uc.user!.displayName,
      //     'photoURL': uc.user!.photoURL,
      //     'email': uc.user!.email,
      //     'createdAt': FieldValue.serverTimestamp(),
      //   }, SetOptions(merge: true));

      _toast(isNew ? '登録しました（Google）' : 'ログインしました（Google）');
      // 画面遷移は _AuthGate がやってくれるので不要
    } on FirebaseAuthException catch (e) {
      // 既に別の方法で登録済みだった場合の救済
      if (e.code == 'account-exists-with-different-credential' &&
          e.email != null) {
        final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(
          e.email!,
        );
        _toast('このメールは既に登録済み: ${methods.join(", ")} でログイン後、設定からGoogle連携してください');
        return;
      }
      _toast('Googleサインイン失敗: ${e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _toast('先にメールアドレスを入力してください');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast('パスワード再設定メールを送信しました');
    } on FirebaseAuthException catch (e) {
      _toast(_friendlyError(e));
    }
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'メールアドレスの形式が正しくありません';
      case 'user-disabled':
        return 'このユーザーは無効化されています';
      case 'user-not-found':
        return 'ユーザーが見つかりません';
      case 'wrong-password':
        return 'パスワードが違います';
      case 'email-already-in-use':
        return 'このメールは既に登録されています';
      case 'weak-password':
        return 'パスワードが弱すぎます';
      default:
        return 'エラー: ${e.code}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? '新規登録' : 'ログイン')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                if (_isSignUp) ...[
                  TextField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '表示名（任意）',
                      hintText: '例：けんと',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  textInputAction: TextInputAction.next,
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
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _handleEmail,
                  icon: Icon(_isSignUp ? Icons.person_add : Icons.login),
                  label: Text(_isSignUp ? 'メールで登録' : 'メールでログイン'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _resetPassword,
                      child: const Text('パスワードをお忘れですか？'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed:
                          _busy
                              ? null
                              : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(_isSignUp ? 'ログインに切替' : '新規登録に切替'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: const [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('または'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _handleGoogle,
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text('Googleで新規登録 : Googleでログイン'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ログイン/登録後は、右上のボタンで「聖地マップ」と「対戦モード」を切替できます。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
