// lib/ads/interstitial_ad_manager.dartは広告の処理をしている。
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class InterstitialAdManager {
  static InterstitialAd? _ad;
  static bool _isLoading = false;

  // テスト用ユニット ID（Android）
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';

  static const String _testInterstitialIOS =
      'ca-app-pub-3940256099942544/4411468910';

  static String get _adUnitId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _testInterstitialIOS;
    }
    return _testInterstitialAndroid;
  }

  /// 事前ロード
  static Future<void> preload() async {
    if (_isLoading || _ad != null) return;

    _isLoading = true;
    await InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _isLoading = false;
          _ad = ad;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoading = false;
          _ad = null;
          debugPrint('Interstitial load failed: $error');
        },
      ),
    );
  }

  /// 表示して、閉じたあとに onFinished を呼ぶ
  static Future<void> show({VoidCallback? onFinished}) async {
    final ad = _ad;
    if (ad == null) {
      // まだ読み込めてないときは、そのまま遷移だけしておく
      onFinished?.call();
      // ついでに裏で次の広告を読み込み開始
      await preload();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
        preload(); // 次の広告を仕込んでおく
        onFinished?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Interstitial show failed: $error');
        ad.dispose();
        _ad = null;
        preload();
        onFinished?.call();
      },
    );

    ad.show();
  }

  static void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
