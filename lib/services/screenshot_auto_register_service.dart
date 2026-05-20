import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screenshot_callback/screenshot_callback.dart';

import 'auto_register_notification_service.dart';
import 'call_card_ocr_parse_service.dart';
import 'screenshot_gallery_finder.dart';

/// MediaStore 스크린샷 이벤트 → 갤러리 스크린샷 OCR → DB 자동저장 (Android 14+, 앱 생존 중).
class ScreenshotAutoRegisterService {
  ScreenshotAutoRegisterService._();
  static final ScreenshotAutoRegisterService instance = ScreenshotAutoRegisterService._();

  static const Duration _writeDelay = Duration(milliseconds: 1000);
  static const Duration _dedupeWindow = Duration(seconds: 15);
  static const Duration _galleryChangeDebounce = Duration(milliseconds: 400);

  ScreenshotCallback? _callback;
  bool _started = false;
  bool _busy = false;
  bool _galleryNotifyEnabled = false;
  String? _lastProcessedKey;
  DateTime? _lastProcessedAt;
  Timer? _galleryDebounce;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 권한·리스너 설정. 거부 시 false (재시도 가능).
  Future<bool> start() async {
    if (!_isAndroid) return false;
    if (!await _ensureMediaPermissions()) {
      debugPrint('ScreenshotAutoRegister: media permission denied');
      return false;
    }

    await AutoRegisterNotificationService.instance.initialize();

    if (!_galleryNotifyEnabled) {
      PhotoManager.addChangeCallback(_onGalleryChanged);
      await PhotoManager.startChangeNotify();
      _galleryNotifyEnabled = true;
    }

    if (!_started) {
      _callback = ScreenshotCallback();
      // ScreenshotCallback() 생성자에서 initialize() 비동기 호출 — 네이티브 준비 대기
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _callback!.addListener(_onScreenshotDetected);
      _started = true;
      debugPrint('ScreenshotAutoRegister: listeners started (callback + gallery)');
    }
    return true;
  }

  void stop() {
    _galleryDebounce?.cancel();
    _callback?.dispose();
    _callback = null;
    _started = false;
    if (_galleryNotifyEnabled) {
      PhotoManager.removeChangeCallback(_onGalleryChanged);
      PhotoManager.stopChangeNotify();
      _galleryNotifyEnabled = false;
    }
  }

  Future<bool> _ensureMediaPermissions() async {
    final pm = await PhotoManager.requestPermissionExtend();
    if (pm.isAuth || pm.hasAccess) return true;

    if (await Permission.photos.request().isGranted) return true;
    if (await Permission.videos.request().isGranted) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  void _onScreenshotDetected() {
    debugPrint('ScreenshotAutoRegister: screenshot_callback fired');
    _scheduleHandle();
  }

  void _onGalleryChanged(MethodCall call) {
    if (call.method != 'change') return;
    debugPrint('ScreenshotAutoRegister: gallery change');
    _scheduleHandle();
  }

  void _scheduleHandle() {
    _galleryDebounce?.cancel();
    _galleryDebounce = Timer(_galleryChangeDebounce, () {
      unawaited(_handleScreenshotEvent());
    });
  }

  Future<void> _handleScreenshotEvent() async {
    if (_busy) return;
    _busy = true;
    try {
      await Future<void>.delayed(_writeDelay);
      if (!await _ensureMediaPermissions()) return;

      final file = await ScreenshotGalleryFinder.fetchLatestScreenshotFile();
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
        debugPrint('ScreenshotAutoRegister: parse invalid for auto-save');
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
      debugPrint('ScreenshotAutoRegister: saved successfully');
    } catch (e, st) {
      debugPrint('ScreenshotAutoRegister error: $e');
      debugPrint('$st');
    } finally {
      _busy = false;
    }
  }
}
