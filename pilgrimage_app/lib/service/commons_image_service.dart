import 'dart:convert';
//ここでは、聖地マップに出力される画像が正常に出力させるようにするコードがある。

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Wikimedia Commons の画像（File:）から、表示用の thumb URL を解決するサービス。
///
/// 受け取れる raw の例:
/// - "commons:Tokyo_Skytree.jpg"
/// - "File:Tokyo_Skytree.jpg"
/// - "Tokyo_Skytree.jpg"
/// - "https://commons.wikimedia.org/wiki/File:Tokyo_Skytree.jpg"
/// - "https://upload.wikimedia.org/wikipedia/commons/thumb/..../Tokyo_Skytree.jpg/640px-Tokyo_Skytree.jpg"
class CommonsImageService {

  void _log(String msg) {
    debugPrint('[CommonsImageService] $msg');
  }
  /// 成功した結果だけキャッシュ（nullはキャッシュしない）
  final Map<String, String> _urlCache = {};

  /// 同じキーの多重リクエスト抑止
  final Map<String, Future<String?>> _inflight = {};

  /// raw から Commons の thumb URL（or 元画像URL）を解決する
  Future<String?> resolveThumbUrl(String raw, {int width = 1200}) {
    if (!isCommonsCandidate(raw)) {
      return Future.value(null);
    }
    final normalized = _normalizeToFileName(raw);

    _log('resolve: raw = "$raw" -> normalized = "$normalized" width = $width');
    if (normalized == null) return Future.value(null);

    // widthもキーに含める（サイズ違いで固定されないように）
    final key = '$normalized@$width';

    final cached = _urlCache[key];
    if (cached != null) return Future.value(cached);

    return _inflight.putIfAbsent(key, () async {
      try {
        final url = await _fetchWithFallback(normalized, preferredWidth: width);
        if (url != null) {
          _urlCache[key] = url;
        }
        // null はキャッシュしない（次回再試行できる）
        return url;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  /// Commons API で解決すべき raw かどうか
  bool isCommonsCandidate(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('commons:') || t.startsWith('File:')) return true;

    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme) {
      final lowered = t.toLowerCase();
      return lowered.endsWith('.jpg') ||
          lowered.endsWith('.jpeg') ||
          lowered.endsWith('.png') ||
          lowered.endsWith('.webp');
    }

    final host = u.host.toLowerCase();
    return host.contains('commons.wikimedia.org') ||
        host.contains('upload.wikimedia.org') ||
        host.endsWith('wikipedia.org');
  }

  /// =========================
  /// Debug helpers
  /// =========================

  /// HEAD で到達性・Content-Type を確認（サーバがHEAD拒否なら 405 などになる）
  Future<void> debugHead(String url) async {
    try {
      final res = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 10));
      debugPrint('HEAD $url -> ${res.statusCode} / ${res.headers['content-type']}');
    } catch (e) {
      debugPrint('HEAD error $url -> $e');
    }
  }

  /// GET(Range) で軽く確認（HEAD拒否されるサイトでも見れることが多い）
  Future<void> debugProbe(String url) async {
    try {
      final res = await http
          .get(
            Uri.parse(url),
            headers: const {'Range': 'bytes=0-200'},
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('GET(range) $url -> ${res.statusCode} / ${res.headers['content-type']}');
    } catch (e) {
      debugPrint('GET(range) error $url -> $e');
    }
  }

  /// =========================
  /// Internal
  /// =========================

  /// raw を「Commonsのファイル名（File:なし）」へ正規化
  String? _normalizeToFileName(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    // commons:xxx
    if (t.startsWith('commons:')) {
      final f = t.substring('commons:'.length).trim();
      return f.isEmpty ? null : _stripFilePrefix(f);
    }

    // File:xxx
    if (t.startsWith('File:')) {
      final f = t.substring('File:'.length).trim();
      return f.isEmpty ? null : f;
    }

    // URLかも
    final uri = Uri.tryParse(t);
    if (uri != null && uri.scheme.isNotEmpty) {
      final host = uri.host.toLowerCase();

      // 1) upload.wikimedia.org (直URL / thumb URL)
      //    ここが「表示できない原因」になりやすいので、ファイル名を抜いてAPIへ回す
      if (host.contains('upload.wikimedia.org')) {
        final segments = uri.pathSegments;

        // /wikipedia/commons/thumb/<h1>/<h2>/<FILENAME>/<thumbname>
        final thumbIdx = segments.indexOf('thumb');
        if (thumbIdx >= 0 && segments.length > thumbIdx + 3) {
          return _safeDecode(segments[thumbIdx + 3]);
        }

        // 元画像URL /wikipedia/commons/<h>/<FILENAME> のような形
        if (segments.isNotEmpty) {
          return _safeDecode(segments.last);
        }

        return null;
      }

      // 2) commons.wikimedia.org (Fileページ)
      if (host.contains('commons.wikimedia.org')) {
        // /wiki/File:xxx
        final segments = uri.pathSegments;
        final idx = segments.indexWhere((s) => s.startsWith('File:'));
        if (idx >= 0) return _stripFilePrefix(_safeDecode(segments[idx]));

        // ?title=File:xxx
        final title = uri.queryParameters['title'];
        if (title != null && title.startsWith('File:')) {
          return _stripFilePrefix(_safeDecode(title));
        }

        return null;
      }

      // 3) wikipedia.org の File ページ (たまに混ざる)
      if (host.endsWith('wikipedia.org')) {
        final segments = uri.pathSegments;
        final idx = segments.indexWhere((s) => s.startsWith('File:'));
        if (idx >= 0) return _stripFilePrefix(_safeDecode(segments[idx]));

        final title = uri.queryParameters['title'];
        if (title != null && title.startsWith('File:')) {
          return _stripFilePrefix(_safeDecode(title));
        }

        return null;
      }

      // それ以外のURL（googleusercontent や一般サイト）は Commons対象外
      return null;
    }

    // 生ファイル名だけ保存しているケースを許容（拡張子チェックは任意）
    return _stripFilePrefix(t);
  }

  String _stripFilePrefix(String fileName) {
    if (fileName.startsWith('File:')) {
      return fileName.substring('File:'.length);
    }
    return fileName;
  }

  String _safeDecode(String s) {
    // すでにデコード済みのこともあるので、失敗しても落とさない
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  Future<String?> _fetchWithFallback(String fileName, {required int preferredWidth}) async {
    // 幅フォールバック（thumb生成失敗に強い）
    final widths = <int>[
      preferredWidth,
      640,
      320,
    ].toList();

    // 重複除去（順序保持）
    final seen = <int>{};
    final unique = <int>[];
    for (final w in widths) {
      if (seen.add(w)) unique.add(w);
    }

    for (final w in unique) {
      final url = await _fetchBestUrlByFileName(fileName, width: w);
      if (url != null) return url;
    }
    return null;
  }

  Future<String?> _fetchBestUrlByFileName(String fileName, {required int width}) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'titles': 'File:$fileName',
      'prop': 'imageinfo',
      // mime/mediatype を取って「表示できるものだけ返す」
      'iiprop': 'url|mime|mediatype',
      'iiurlwidth': '$width',
      'format': 'json',
      'formatversion': '2',
      'redirects': '1',
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    _log('API status=${response.statusCode} title="File:$fileName" width=$width');
    
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    final pages = decoded?['query']?['pages'];
    if (pages is! List || pages.isEmpty) return null;

    final page = pages.first;
    if (page is! Map) return null;

    // missing の場合
    if (page['missing'] == true) {
      _log('API status=${response.statusCode} title="File:$fileName" width=$width');
       return null;
    }

    final info = page['imageinfo'];
    if (info is! List || info.isEmpty) return null;

    final first = info.first;
    if (first is! Map) return null;

    final thumb = first['thumburl']?.toString();
    final url = first['url']?.toString();
    final mime = (first['mime'] ?? '').toString().toLowerCase();
    final mediatype = (first['mediatype'] ?? '').toString().toUpperCase();

    // thumb があればそれが最優先（表示＆通信量の面で安定）
    if ((thumb ?? '').isNotEmpty) return thumb;

    // thumb が無い場合、元が画像(Bitmap)でないと Image.network で死にやすい
    if ((url ?? '').isEmpty) return null;

    final isBitmap = mediatype == 'BITMAP';
    final isSvg = mime.contains('svg');
    final isTiff = mime.contains('tiff');
    final isPdf = mime.contains('pdf');
    final isVideo = mediatype == 'VIDEO';

    if (!isBitmap || isSvg || isTiff || isPdf || isVideo) {
      // ここは「表示できない可能性が高い」ので null にしてUI側で別処理推奨
      return null;
    }

    return url;
  }
}
