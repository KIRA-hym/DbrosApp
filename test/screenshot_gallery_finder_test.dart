import 'package:flutter_test/flutter_test.dart';

import 'package:dbros_app/services/screenshot_gallery_finder.dart';

void main() {
  group('ScreenshotGalleryFinder.looksLikeScreenshotText', () {
    test('matches English and Korean hints', () {
      expect(ScreenshotGalleryFinder.looksLikeScreenshotText('Screenshot_20260520.png'), isTrue);
      expect(ScreenshotGalleryFinder.looksLikeScreenshotText('스크린샷_20260520.jpg'), isTrue);
      expect(ScreenshotGalleryFinder.looksLikeScreenshotText('/Pictures/Screenshots/foo.png'), isTrue);
    });

    test('rejects normal photos', () {
      expect(ScreenshotGalleryFinder.looksLikeScreenshotText('IMG_20260520.jpg'), isFalse);
      expect(ScreenshotGalleryFinder.looksLikeScreenshotText(null), isFalse);
    });
  });
}
