import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config/home_promo_config.dart';

/// 홈 하단 전체 영역에 맞춰 유튜브 임베드를 표시합니다.
class HomePromoYoutube extends StatefulWidget {
  const HomePromoYoutube({super.key});

  @override
  State<HomePromoYoutube> createState() => _HomePromoYoutubeState();
}

class _HomePromoYoutubeState extends State<HomePromoYoutube> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  /// 인앱 WebView에서 유튜브가 빈 화면으로 나오는 경우가 있어 일반 크롬(모바일) UA를 맞춥니다.
  static const _chromeMobileUa =
      'Mozilla/5.0 (Linux; Android 13; SM-S901N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// embed URL을 iframe으로 감싸 Referrer / 동적 삽입 요구사항을 맞춥니다.
  /// (직접 embed 로드 시 오류 153 동영상 플레이어 구성 오류 완화)
  static String _embedPageHtml(Uri embedUri) {
    final src = embedUri.toString().replaceAll('&', '&amp;');
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="referrer" content="strict-origin-when-cross-origin">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden;}
iframe{position:fixed;left:0;top:0;width:100%;height:100%;border:0;}
</style>
</head>
<body>
<iframe src="$src" referrerpolicy="strict-origin-when-cross-origin"
  allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen"
  allowfullscreen></iframe>
</body>
</html>''';
  }

  @override
  void initState() {
    super.initState();
    final id = kHomeYoutubeVideoId.trim();
    if (id.isEmpty) return;
    final uri = buildHomeYoutubeEmbedUri(id);
    _initWebView(uri);
  }

  Future<void> _initWebView(Uri uri) async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF16181D))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (WebResourceError error) {
            if (!mounted) return;
            final main = error.isForMainFrame ?? true;
            if (main) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      );

    await controller.setUserAgent(_chromeMobileUa);

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
    }

    await controller.loadHtmlString(
      _embedPageHtml(uri),
      baseUrl: 'https://www.youtube.com/',
    );

    if (mounted) {
      setState(() => _controller = controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = kHomeYoutubeVideoId.trim();
    if (id.isEmpty) {
      return SizedBox.expand(
        child: Container(
          color: const Color(0xFF16181D),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'home_promo_config.dart 의\nkHomeYoutubeVideoId 에\n영상·채널 ID를 넣으면 재생됩니다',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6E717C),
                  height: 1.35,
                ),
          ),
        ),
      );
    }
    if (_controller == null) {
      return SizedBox.expand(
        child: Container(
          color: const Color(0xFF16181D),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(color: Color(0xFFFFC700)),
        ),
      );
    }

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller!),
          if (_loading)
            Container(
              color: const Color(0xFF16181D),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: Color(0xFFFFC700)),
            ),
          if (_error != null && !_loading)
            Container(
              color: const Color(0xE016181D),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Text(
                '영상을 불러오지 못했습니다.\n$_error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFFF5252),
                      height: 1.35,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
