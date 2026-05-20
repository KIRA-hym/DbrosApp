import 'dart:io' show File;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:photo_manager/photo_manager.dart';

/// 갤러리에서 스크린샷 이미지 조회 (삼성·Android 14+ 포함).
class ScreenshotGalleryFinder {
  ScreenshotGalleryFinder._();

  static const Duration _maxAge = Duration(seconds: 45);
  static const int _scanPerAlbum = 12;

  static const List<String> _nameHints = [
    'screenshot',
    'screen_shot',
    'screen shot',
    'screencapture',
    'screen_capture',
    'screen capture',
    '스크린샷',
    '스크린 샷',
    '캡처',
    'capture',
  ];

  static const List<String> _albumHints = [
    'screenshot',
    'screen shots',
    'screen_shots',
    'screencaptures',
    '스크린샷',
    '스크린 샷',
    '캡처',
    'capture',
  ];

  static bool looksLikeScreenshotText(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    for (final hint in _nameHints) {
      final h = hint.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
      if (normalized.contains(h)) return true;
    }
    return false;
  }

  static bool _albumLooksLikeScreenshots(AssetPathEntity album) {
    final name = album.name.toLowerCase();
    if (_albumHints.any((h) => name.contains(h))) return true;
    return looksLikeScreenshotText(album.name);
  }

  static bool _isRecentEnough(DateTime? created) {
    if (created == null) return true;
    return DateTime.now().difference(created) <= _maxAge;
  }

  /// 스크린샷 앨범 우선 → 최근 이미지 중 파일명·경로로 스크린샷 후보 선택.
  static Future<File?> fetchLatestScreenshotFile() async {
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );
      if (albums.isEmpty) return null;

      final screenshotAlbums = albums.where(_albumLooksLikeScreenshots).toList();
      final searchOrder = <AssetPathEntity>[
        ...screenshotAlbums,
        ...albums.where((a) => !screenshotAlbums.contains(a)),
      ];

      AssetEntity? best;
      DateTime? bestTime;

      for (final album in searchOrder) {
        final assets = await album.getAssetListPaged(page: 0, size: _scanPerAlbum);
        for (final asset in assets) {
          if (!await _assetLooksLikeScreenshot(asset)) continue;
          final created = asset.createDateTime;
          if (!_isRecentEnough(created)) continue;
          if (bestTime == null || !created.isBefore(bestTime)) {
            best = asset;
            bestTime = created;
          }
        }
        if (best != null && screenshotAlbums.contains(album)) break;
      }

      if (best == null) {
        debugPrint('ScreenshotGalleryFinder: no recent screenshot asset');
        return null;
      }

      final file = await best.file;
      debugPrint('ScreenshotGalleryFinder: picked ${best.title} (${file?.path})');
      return file;
    } catch (e, st) {
      debugPrint('ScreenshotGalleryFinder error: $e');
      debugPrint('$st');
      return null;
    }
  }

  static Future<bool> _assetLooksLikeScreenshot(AssetEntity asset) async {
    if (looksLikeScreenshotText(asset.title)) return true;
    if (looksLikeScreenshotText(asset.relativePath)) return true;
    final file = await asset.file;
    if (file != null && looksLikeScreenshotText(file.path)) return true;
    return false;
  }
}
