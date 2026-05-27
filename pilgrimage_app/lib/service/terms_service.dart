// lib/service/terms_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class TermsService {
  /// 利用規約のバージョン
  /// ※ 内容を変えたら 1 → 2 → 3... と上げていく
  static const int _currentVersion = 1;

  /// デバッグ用: true にすると「毎回」利用規約を出す
  static const bool debugForceShow = false;

  static String get _prefsKey => 'terms_accepted_v$_currentVersion';

  /// 今のバージョンの利用規約を「表示する必要があるか」
  static Future<bool> shouldShowTerms() async {
    if (debugForceShow) return true; // 強制表示モード

    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(_prefsKey) ?? false;
    return !accepted;
  }

  /// 今のバージョンの利用規約に同意したことを保存
  static Future<void> acceptCurrentTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  /// デバッグ用: 同意状態をクリアして「未同意」に戻す
  static Future<void> clearAcceptedForDebug() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
