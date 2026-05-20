import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screenshot_callback/screenshot_callback.dart';

import 'auto_register_notification_service.dart';
import 'call_card_ocr_parse_service.dart';
import 'screenshot_auto_debug_log.dart';
import 'screenshot_gallery_finder.dart';

/// MediaStore 변경 / 스크린샷 콜백 → 최근 이미지 OCR → DB 자동저장 (Android, 앱 생존 중).
class ScreenshotAutoRegisterService {
  ScreenshotAutoRegisterService._();
  static final ScreenshotAutoRegisterService instance = ScreenshotAutoRegisterService._();

  static const MethodChannel _nativeGalleryObserver = MethodChannel('dbros.app/gallery_observer');

  static const Duration _writeDelay = Duration(milliseconds: 1500);
  static const Duration _dedupeWindow = Duration(seconds: 15);
  static const Duration _galleryChangeDebounce = Duration(milliseconds: 450);

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
    ScreenshotAutoDebugLog.add('start() — 스크린샷 자동등록 초기화');

    if (!await _ensureMediaPermissions()) {
      ScreenshotAutoDebugLog.add('실패: 미디어 권한 없음(사진 접근을 허용했는지 확인)');
      debugPrint('ScreenshotAutoRegister: media permission denied');
      return false;
    }

    await AutoRegisterNotificationService.instance.initialize();

    await _ensureNativeGalleryObserver();

    if (!_galleryNotifyEnabled) {
      PhotoManager.addChangeCallback(_onGalleryChanged);
      await PhotoManager.startChangeNotify();
      _galleryNotifyEnabled = true;
    }

    if (!_started) {
      _callback = ScreenshotCallback();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _callback!.addListener(_onScreenshotDetected);
      _started = true;
      ScreenshotAutoDebugLog.add('리스너 시작: 네이티브 MediaStore + screenshot_callback + photo_manager');
      debugPrint('ScreenshotAutoRegister: listeners started (native+screenshot_plugin+gallery)');
    }
    return true;
  }

  Future<void> _ensureNativeGalleryObserver() async {
    _nativeGalleryObserver.setMethodCallHandler((call) async {
      if (call.method == 'onChanged') {
        ScreenshotAutoDebugLog.add('이벤트: 네이티브 MediaStore(이미지) 변경');
        debugPrint('ScreenshotAutoRegister: native ContentObserver fired');
        _scheduleHandle();
      }
    });
    try {
      await _nativeGalleryObserver.invokeMethod<void>('start');
      ScreenshotAutoDebugLog.add('네이티브 ContentObserver 등록 완료');
    } catch (e) {
      ScreenshotAutoDebugLog.add('경고: 네이티브 observer start 실패 → $e');
      debugPrint('ScreenshotAutoRegister: native observer start failed: $e');
    }
  }

  Future<void> _stopNativeGalleryObserver() async {
    try {
      await _nativeGalleryObserver.invokeMethod<void>('stop');
    } catch (_) {}
    try {
      _nativeGalleryObserver.setMethodCallHandler(null);
    } catch (_) {}
  }

  void stop() {
    _galleryDebounce?.cancel();
    unawaited(_stopNativeGalleryObserver());
    _callback?.dispose();
    _callback = null;
    _started = false;
    if (_galleryNotifyEnabled) {
      PhotoManager.removeChangeCallback(_onGalleryChanged);
      PhotoManager.stopChangeNotify();
      _galleryNotifyEnabled = false;
    }
    ScreenshotAutoDebugLog.add('stop() — 리스너 해제');
  }

  Future<bool> _ensureMediaPermissions() async {
    final pm = await PhotoManager.requestPermissionExtend();
    ScreenshotAutoDebugLog.add(
      '사진 권한: isAuth=${pm.isAuth} hasAccess=${pm.hasAccess} (${pm.toString()})',
    );
    if (pm.isAuth || pm.hasAccess) return true;

    if (await Permission.photos.request().isGranted) {
      ScreenshotAutoDebugLog.add('사진 권한: permission_handler photos 허용');
      return true;
    }
    if (await Permission.videos.request().isGranted) return true;

    final storage = await Permission.storage.request();
    final ok = storage.isGranted;
    if (!ok) ScreenshotAutoDebugLog.add('저장공간(storage) 권한: 거부');
    return ok;
  }

  void _onScreenshotDetected() {
    ScreenshotAutoDebugLog.add('이벤트: screenshot_callback(플러그인 감지)');
    debugPrint('ScreenshotAutoRegister: screenshot_callback fired');
    _scheduleHandle();
  }

  void _onGalleryChanged(MethodCall call) {
    if (call.method != 'change') return;
    ScreenshotAutoDebugLog.add('이벤트: PhotoManager.galleryChanged');
    _scheduleHandle();
  }

  void _scheduleHandle() {
    _galleryDebounce?.cancel();
    ScreenshotAutoDebugLog.add('처리 예약 (${_galleryChangeDebounce.inMilliseconds}ms 디바운스 후 실행)');
    _galleryDebounce = Timer(_galleryChangeDebounce, () {
      unawaited(_handleScreenshotEvent());
    });
  }

  Future<void> _handleScreenshotEvent() async {
    if (_busy) {
      ScreenshotAutoDebugLog.add('건너뜀: 이전 처리가 아직 진행 중');
      return;
    }
    _busy = true;
    try {
      ScreenshotAutoDebugLog.add('처리 시작 — ${_writeDelay.inMilliseconds}ms 대기 후 갤러리 조회');
      await Future<void>.delayed(_writeDelay);
      if (!await _ensureMediaPermissions()) {
        ScreenshotAutoDebugLog.add('중단: 권한 재확인 실패');
        return;
      }

      final strict = await ScreenshotGalleryFinder.fetchLatestScreenshotFile();
      final file = strict ??
          await ScreenshotGalleryFinder.fetchRecentImageFromScreenshotsFolder(
            maxAge: const Duration(seconds: 35),
          );
      if (strict != null) {
        ScreenshotAutoDebugLog.add('후보 파일(1순위): ${strict.path}');
      } else if (file != null) {
        ScreenshotAutoDebugLog.add('후보 파일(폴더 폴백): ${file.path}');
      }
      if (file == null) {
        ScreenshotAutoDebugLog.add('결과: 스크린샷 후보 이미지 없음(OCR 진행 안 함)');
        debugPrint('ScreenshotAutoRegister: no screenshot candidate file');
        return;
      }

      final dedupeKey = file.path;
      final now = DateTime.now();
      if (_lastProcessedKey == dedupeKey &&
          _lastProcessedAt != null &&
          now.difference(_lastProcessedAt!) < _dedupeWindow) {
        ScreenshotAutoDebugLog.add('건너뜀: 같은 경로 디바운스($_dedupeWindow)');
        return;
      }

      ScreenshotAutoDebugLog.add('OCR·파싱 실행…');
      final logData = await CallCardOcrParseService.parseImageFile(
        file,
        ocrSource: 'screenshot_auto',
      );
      if (!CallCardOcrParseService.isValidForAutoSave(logData)) {
        ScreenshotAutoDebugLog.add(
          '결과: 파싱됐으나 자동저장 조건 불충족 (요금·출발·도착 등)',
        );
        debugPrint('ScreenshotAutoRegister: parse invalid for auto-save');
        return;
      }

      final saved = await CallCardOcrParseService.saveLogToDatabase(
        logData,
        imagePrefix: 'screenshot',
      );
      if (!saved) {
        ScreenshotAutoDebugLog.add('결과: DB 저장 호출 후 실패 처리');
        return;
      }

      _lastProcessedKey = dedupeKey;
      _lastProcessedAt = now;

      await AutoRegisterNotificationService.instance.showAutoRegisterComplete();
      ScreenshotAutoDebugLog.add('성공: DB 저장 후 완료 알림 표시');
      debugPrint('ScreenshotAutoRegister: saved successfully');
    } catch (e, st) {
      ScreenshotAutoDebugLog.add('오류: $e');
      debugPrint('ScreenshotAutoRegister error: $e');
      debugPrint('$st');
    } finally {
      _busy = false;
    }
  }
}
