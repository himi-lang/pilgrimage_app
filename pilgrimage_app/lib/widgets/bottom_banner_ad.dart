// lib/widgets/bottom_banner_ad.dart
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class BottomBannerAd extends StatefulWidget {
  const BottomBannerAd({super.key, this.reservedHeight = 60});

  // 広告ロード前から下部スロットを確保してレイアウトジャンプを防ぐ
  final double reservedHeight;

  @override
  State<BottomBannerAd> createState() => _BottomBannerAdState();
}

class _BottomBannerAdState extends State<BottomBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();

    _bannerAd = BannerAd(
      size: AdSize.banner,
      // ★ Android 用テストバナーの広告ユニットID
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load: $error');
          ad.dispose();
        },
      ),
      request: const AdRequest(),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.reservedHeight,
      child: Center(
        child:
            (!_isLoaded || _bannerAd == null)
                ? const SizedBox.shrink()
                : SizedBox(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
      ),
    );
  }
}
