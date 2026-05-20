import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screenshot_callback/screenshot_callback.dart';

import 'auto_register_notification_service.dart';
import 'call_card_ocr_parse_service.dart';

/// MediaStore 스크린샷 이벤트 → 최신 갤러리 이미지 OCR → DB 자동저장 (Android, 앱 생존 중).
class ScreenshotAutoRegisterService {
  ScreenshotAutoRegisterService._();
  static final ScreenshotAutoRegisterService instance = ScreenshotAutoRegisterService._();

  static const Duration _writeDelay = Duration(milliseconds: 800);
  static const Duration _dedupeWindow = Duration(seconds: 15);

  ScreenshotCallback? _callback;
  bool _started = false;
  bool _busy = false;
  String? _lastProcessedKey;
  DateTime? _lastProcessedAt;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> start() async {
    if (!_isAndroid || _started) return;
    if (!await _ensureMediaPermissions()) {
      debugPrint('ScreenshotAutoRegister: media permission denied');
      return;
    }

    await AutoRegisterNotificationService.instance.initialize();

    _callback = ScreenshotCallback();
    _callback!.addListener(_onScreenshotDetected);
    _started = true;
    debugPrint('ScreenshotAutoRegister: listener started');
  }

  void stop() {
    _callback?.dispose();
    _callback = null;
    _started = false;
  }

  Future<bool> _ensureMediaPermissions() async {
    final pm = await PhotoManager.requestPermissionExtend();
    if (pm.isAuth) return true;

    var photos = await Permission.photos.request();
    if (photos.isGranted) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  void _onScreenshotDetected() {
    unawaited(_handleScreenshotEvent());
  }

  Future<void> _handleScreenshotEvent() async {
    if (_busy) return;
    _busy = true;
    try {
      await Future<void>.delayed(_writeDelay);
      if (!await _ensureMediaPermissions()) return;

      final file = await _fetchLatestGalleryImageFile();
      if (file == null) return;

      final dedupeKey = file.path;
      final now = DateTime.now();
      if (_lastProcessedKey == dedupeKey &&
          _lastProcessedAt != null &&
          now.difference(_lastProcessedAt!) < _dedupeWindow) {
        return;
      }

      final logData = await CallCardOcrParseService.parseImageFile(
        file,
        ocrSource: 'screenshot_auto',
      );
      if (!CallCardOcrParseService.isValidForAutoSave(logData)) {
        return;
      }

      final saved = await CallCardOcrParseService.saveLogToDatabase(
        logData,
        imagePrefix: 'screenshot',
      );
      if (!saved) return;

      _lastProcessedKey = dedupeKey;
      _lastProcessedAt = now;

      await AutoRegisterNotificationService.instance.showAutoRegisterComplete();
    } catch (e, st) {
      debugPrint('ScreenshotAutoRegister error: $e');
      debugPrint('$st');
    } finally {
      _busy = false;
    }
  }

  Future<File?> _fetchLatestGalleryImageFile() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (paths.isEmpty) return null;

    final recentAlbum = paths.first;
    final assets = await recentAlbum.getAssetListPaged(page: 0, size: 1);
    if (assets.isEmpty) return null;

    return assets.first.file;
  }
}
