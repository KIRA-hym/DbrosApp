import 'dart:io' show File;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:photo_manager/photo_manager.dart';

/// 갤러리에서 스크린샷 이미지 조회 (삼성·Android 14+ 포함).
class ScreenshotGalleryFinder {
  ScreenshotGalleryFinder._();

  static const Duration _defaultMaxAge = Duration(seconds: 45);
  static const int _scanPerAlbum = 40;

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
    '캡쳐',
    'capture',
  ];

  static const List<String> _albumHints = [
    'screenshot',
    'screen shots',
    'screen_shots',
    'screencaptures',
    '스크린샷',
    '스크린 샷',
    '스크린캡처',
    '캡처',
    'capture',
  ];

  /// 파일명/경로 상 스크린샷 폴더 패턴 (파일명에 screenshot 이 없어도 DCIM/Screenshots 등 허용).
  static bool looksLikeScreenshotsFolderPath(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    final norm = path.toLowerCase().replaceAll(r'\', '/');
    if (norm.contains('/screenshots')) return true;
    if (norm.contains('screenshots/')) return true;
    if (norm.contains('/pictures/screenshot')) return true;
    if (norm.contains('dcim/screenshot')) return true;
    return false;
  }

  static bool looksLikeScreenshotText(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    for (final hint in _nameHints) {
      final h = hint.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
      if (h.isEmpty) continue;
      if (normalized.contains(h)) return true;
    }
    return false;
  }

  static bool _albumLooksLikeScreenshots(AssetPathEntity album) {
    final name = album.name.toLowerCase();
    if (_albumHints.any((h) => name.contains(h))) return true;
    return looksLikeScreenshotText(album.name);
  }

  static bool _isRecentEnough(DateTime created, Duration maxAge) {
    return DateTime.now().difference(created) <= maxAge;
  }

  /// 스크린샷 앨범 우선 → 파일명 또는 스크린샷 폴더 경로로 후보 선택.
  static Future<File?> fetchLatestScreenshotFile({
    Duration maxAge = _defaultMaxAge,
  }) async {
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
          if (!await _assetLooksLikeScreenshotAsset(asset)) continue;
          final created = asset.createDateTime;
          if (!_isRecentEnough(created, maxAge)) continue;
          if (bestTime == null || !created.isBefore(bestTime)) {
            best = asset;
            bestTime = created;
          }
        }
        if (best != null && screenshotAlbums.contains(album)) break;
      }

      if (best == null) {
        debugPrint('ScreenshotGalleryFinder: no recent screenshot-named asset');
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

  /// 파일명 없이 **스크린샷 폴더**(경로) 또는 스크린샷 앨범의 가장 최근 이미지.
  static Future<File?> fetchRecentImageFromScreenshotsFolder({
    Duration maxAge = _defaultMaxAge,
  }) async {
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );
      if (albums.isEmpty) return null;

      final namedScreenshotAlbums =
          albums.where(_albumLooksLikeScreenshots).toList();
      final ordered = <AssetPathEntity>[
        ...namedScreenshotAlbums,
        ...albums.where((a) => !namedScreenshotAlbums.contains(a)),
      ];

      AssetEntity? best;
      DateTime? bestTime;

      Future<bool> inScreenshotsLocation(AssetEntity asset) async {
        if (looksLikeScreenshotsFolderPath(asset.relativePath)) return true;
        final f = await asset.file;
        return looksLikeScreenshotsFolderPath(f?.path);
      }

      for (final album in ordered) {
        final fromNamedAlbum = namedScreenshotAlbums.contains(album);
        final assets =
            await album.getAssetListPaged(page: 0, size: _scanPerAlbum);

        for (final asset in assets) {
          if (!fromNamedAlbum && !(await inScreenshotsLocation(asset))) continue;

          final created = asset.createDateTime;
          if (!_isRecentEnough(created, maxAge)) continue;

          if (bestTime == null || !created.isBefore(bestTime)) {
            best = asset;
            bestTime = created;
          }
        }
        if (best != null && fromNamedAlbum) break;
      }

      if (best == null) return null;
      final file = await best.file;
      debugPrint(
        'ScreenshotGalleryFinder(folder fallback): ${best.title} path=${file?.path}',
      );
      return file;
    } catch (e, st) {
      debugPrint('ScreenshotGalleryFinder folder fallback error: $e');
      debugPrint('$st');
      return null;
    }
  }

  static Future<bool> _assetLooksLikeScreenshotAsset(AssetEntity asset) async {
    if (looksLikeScreenshotText(asset.title)) return true;
    if (looksLikeScreenshotsFolderPath(asset.relativePath)) return true;
    final file = await asset.file;
    if (file != null) {
      if (looksLikeScreenshotText(file.path)) return true;
      if (looksLikeScreenshotsFolderPath(file.path)) return true;
    }
    return false;
  }
}
