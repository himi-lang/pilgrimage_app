import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static Future<void> signOutAndGoRoot(BuildContext context) async {
    try {
      if (!kIsWeb) {
        try {
          await GoogleSignIn().signOut(); // v7のサインアウト
        } catch (_) {
          // Google連携なし等は無視
        }
      }
      await FirebaseAuth.instance.signOut();
    } finally {
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    }
  }
}
