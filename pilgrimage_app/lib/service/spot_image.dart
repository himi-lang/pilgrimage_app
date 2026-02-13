import 'package:flutter/material.dart';
import './commons_image_service.dart'; // パスはあなたの構成に合わせて変更してOK

class SpotImage extends StatelessWidget {
  static final CommonsImageService _commons = CommonsImageService();

  const SpotImage({
    super.key,
    required this.raw,
    this.fit = BoxFit.cover,
    this.width = 640,
    this.cacheWidth,
    this.placeholder,
  });

  final String raw;
  final BoxFit fit;
  final int width;
  final int? cacheWidth;
  final Widget? placeholder;

  bool _isHttpUrl(String s) {
    final u = Uri.tryParse(s.trim());
    return u != null && (u.scheme == 'http' || u.scheme == 'https');
  }

  bool _isWikimediaUrl(String s) {
    final u = Uri.tryParse(s.trim());
    if (u == null || !u.hasScheme) return false;
    final host = u.host.toLowerCase();
    return host.contains('wikimedia.org') || host.endsWith('wikipedia.org');
  }

  Future<String?> _getDisplayUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // 一般サイトURLなら Commons解決せずそのまま使う
    if (_isHttpUrl(s) && !_isWikimediaUrl(s)) {
      debugPrint('[SpotImage] direct url: $s');
      return s;
    }

    // Commons系なら解決を試す
    final resolved = await _commons.resolveThumbUrl(s, width: width);
    debugPrint('[SpotImage] resolved: raw="$s" -> "$resolved"');

    // 解決できない場合、rawがURLならrawを使う（File名だけ等はnull）
    return resolved ?? (_isHttpUrl(s) ? s : null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getDisplayUrl(raw),
      builder: (context, snapshot) {
        // 読み込み中
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder ??
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
        }

        final url = snapshot.data;
        if (url == null) {
          debugPrint('[SpotImage] url is null. raw="$raw"');
          return const Icon(Icons.image_not_supported);
        }

        return Image.network(
          url,
          fit: fit,
          cacheWidth: cacheWidth ?? width,
          headers: const {'User-Agent': 'Mozilla/5.0'},
          errorBuilder: (context, error, stack) {
            debugPrint('[Image.network] url=$url');
            debugPrint('[Image.network] error=$error');
            if (stack != null) debugPrint(stack.toString());
            return const Icon(Icons.broken_image);
          },
        );
      },
    );
  }
}
