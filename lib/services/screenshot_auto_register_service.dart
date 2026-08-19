import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screenshot_callback/screenshot_callback.dart';

import 'auto_register_notification_service.dart';
import 'notification_permission_service.dart';
import 'call_card_ocr_parse_service.dart';
import 'settings_service.dart';
import 'screenshot_auto_debug_log.dart';
import 'screenshot_gallery_finder.dart';
import 'today_stats_notification_service.dart';

/// MediaStore 변경 / 스크린샷 콜백 → 최근 이미지 OCR → DB 자동저장 (Android, 앱 생존 중).
class ScreenshotAutoRegisterService {
  ScreenshotAutoRegisterService._();
  static final ScreenshotAutoRegisterService instance = ScreenshotAutoRegisterService._();

  static const MethodChannel _nativeGalleryObserver = MethodChannel('dbros.app/gallery_observer');

  static const Duration _writeDelay = Duration(milliseconds: 750);
  /// 첫 조회 실패 시 MediaStore 안정화를 위해 추가 대기 후 1회만 재조회.
  static const Duration _retryCandidateDelay = Duration(milliseconds: 850);
  static const Duration _dedupeWindow = Duration(seconds: 20);
  static const Duration _fingerprintDedupeWindow = Duration(seconds: 30);
  static const Duration _galleryChangeDebounce = Duration(milliseconds: 330);
  /// 같은 스크린샷이 다른 MediaStore id 로 두 번 들어오는 등 바이트는 같을 때 (제조사/갤러리 버그).
  static const Duration _imageSampleDedupeWindow = Duration(seconds: 90);
  static const int _imageSignatureMaxBytes = 256 * 1024;

  ScreenshotCallback? _callback;
  bool _started = false;
  bool _nativeBridgeStarted = false;
  bool _busy = false;
  bool _pendingRetryAfterBusy = false;
  bool _galleryNotifyEnabled = false;
  String? _lastProcessedKey;
  DateTime? _lastProcessedAt;
  String? _lastSaveFingerprint;
  DateTime? _lastSaveFingerprintAt;
  String? _lastImageSampleSignature;
  DateTime? _lastImageSampleSignatureAt;
  Timer? _galleryDebounce;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 설정값에 맞춰 리스너 시작 또는 해제. [main]·재개·설정 토글에서 호출.
  Future<void> syncWithSettingsPreference() async {
    if (!_isAndroid) return;
    if (!SettingsService.screenshotAutoRegisterEnabled) {
      stop();
      return;
    }
    await start();
  }

  /// 앱이 포그라운드로 돌아왔을 때, 백그라운드 상태여서 감지하지 못한 최신 스크린샷이 있는지 수동으로 1회 확인.
  Future<void> checkRecentScreenshotOnResume() async {
    if (!_isAndroid || !SettingsService.screenshotAutoRegisterEnabled) return;
    ScreenshotAutoDebugLog.add('앱 재개(resumed)됨: 백그라운드에서 놓친 스크린샷 1회 확인');
    _scheduleHandle();
  }

  /// 권한·리스너 설정. 거부 시 false (재시도 가능).
  Future<bool> start() async {
    if (!_isAndroid) return false;
    ScreenshotAutoDebugLog.add('start() — 스크린샷 자동등록 초기화');

    if (!await _ensureMediaPermissions()) {
      ScreenshotAutoDebugLog.add('실패: 미디어 권한 없음(사진 접근을 허용했는지 확인)');
      debugPrint('ScreenshotAutoRegister: media permission denied');
      return false;
    }

    if (!await NotificationPermissionService.requestIfNeeded()) {
      ScreenshotAutoDebugLog.add('실패: 알림 권한 없음(설정에서 알림을 허용해 주세요)');
      debugPrint('ScreenshotAutoRegister: notification permission denied');
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
    if (_nativeBridgeStarted) return;

    _nativeGalleryObserver.setMethodCallHandler((call) async {
      if (call.method == 'onChanged') {
        ScreenshotAutoDebugLog.add('이벤트: 네이티브 MediaStore(이미지) 변경');
        debugPrint('ScreenshotAutoRegister: native ContentObserver fired');
        _scheduleHandle();
      }
    });
    try {
      await _nativeGalleryObserver.invokeMethod<void>('start');
      _nativeBridgeStarted = true;
      ScreenshotAutoDebugLog.add('네이티브 ContentObserver 등록 완료');
    } catch (e) {
      ScreenshotAutoDebugLog.add('경고: 네이티브 observer start 실패 → $e');
      debugPrint('ScreenshotAutoRegister: native observer start failed: $e');
    }
    
    // 자동감지 Foreground Service가 뜬 직후 고정알림을 재발행하여 고정알림을 최상단으로 끌어올림
    Future.delayed(const Duration(milliseconds: 300), () {
      TodayStatsNotificationService.instance.renotifyIfEnabled();
    });
  }

  Future<void> _stopNativeGalleryObserver() async {
    try {
      await _nativeGalleryObserver.invokeMethod<void>('stop');
    } catch (_) {}
    try {
      _nativeGalleryObserver.setMethodCallHandler(null);
    } catch (_) {}
    _nativeBridgeStarted = false;
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
      _pendingRetryAfterBusy = true;
      ScreenshotAutoDebugLog.add('건너뜀: 이전 처리가 아직 진행 중 (종료 후 1회 재예약)');
      return;
    }
    _busy = true;
    var suppressPendingRetryDueToSave = false;
    try {
      ScreenshotAutoDebugLog.add('처리 시작 — ${_writeDelay.inMilliseconds}ms 대기 후 갤러리 조회');
      await Future<void>.delayed(_writeDelay);
      if (!await _ensureMediaPermissions()) {
        ScreenshotAutoDebugLog.add('중단: 권한 재확인 실패');
        return;
      }

      var pick = await _pickScreenshotCandidate();
      if (pick.file == null) {
        ScreenshotAutoDebugLog.add(
          '후보 없음 → ${_retryCandidateDelay.inMilliseconds}ms 후 1회 재조회',
        );
        await Future<void>.delayed(_retryCandidateDelay);
        pick = await _pickScreenshotCandidate();
      }
      final file = pick.file;
      if (file != null && pick.tag != null) {
        ScreenshotAutoDebugLog.add('후보 파일(${pick.tag}): ${file.path}');
      }
      if (file == null) {
        ScreenshotAutoDebugLog.add('결과: 스크린샷 후보 이미지 없음(OCR 진행 안 함)');
        debugPrint('ScreenshotAutoRegister: no screenshot candidate file');
        return;
      }

      final now = DateTime.now();
      final imageSig = await _fileLeadingBytesSignature(file);
      if (imageSig != null &&
          imageSig == _lastImageSampleSignature &&
          _lastImageSampleSignatureAt != null &&
          now.difference(_lastImageSampleSignatureAt!) < _imageSampleDedupeWindow) {
        ScreenshotAutoDebugLog.add(
          '건너뜀: 동일 이미지 샘플 해시($_imageSampleDedupeWindow)·다른 파일/갤러리 id 중복 무시',
        );
        return;
      }

      final dedupeKey = _dedupeKeyForScreenshotPath(file.path);
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
          '결과: 스크린샷 자동저장 제외(콜카드 UI 신호 부족·앱 OCR/디버그 화면 가능성 또는 약한 카카오 추정)',
        );
        debugPrint('ScreenshotAutoRegister: parse invalid for screenshot auto-save');
        return;
      }

      final fp = CallCardOcrParseService.autoSaveDuplicateFingerprint(logData);
      final now2 = DateTime.now();
      if (fp.isNotEmpty &&
          fp == _lastSaveFingerprint &&
          _lastSaveFingerprintAt != null &&
          now2.difference(_lastSaveFingerprintAt!) < _fingerprintDedupeWindow) {
        ScreenshotAutoDebugLog.add(
          '건너뜀: 동일 인식 내용 디바운스($_fingerprintDedupeWindow)·이중 저장 방지',
        );
        return;
      }

      final insertedId = await CallCardOcrParseService.saveLogToDatabase(
        logData,
        imagePrefix: 'screenshot',
        originalDate: file.existsSync() ? file.lastModifiedSync() : DateTime.now(),
      );
      if (insertedId == null) {
        ScreenshotAutoDebugLog.add('결과: DB 저장 호출 후 실패 처리');
        return;
      }

      final doneAt = DateTime.now();
      _lastProcessedKey = dedupeKey;
      _lastProcessedAt = doneAt;
      _lastSaveFingerprint = fp;
      _lastSaveFingerprintAt = doneAt;
      if (imageSig != null) {
        _lastImageSampleSignature = imageSig;
        _lastImageSampleSignatureAt = doneAt;
      }

      try {
        final missing = CallCardOcrParseService.getMissingFieldsList(logData);

        AutoRegisterNotificationService.instance.showAutoRegisterComplete(
          logId: insertedId,
          missingFields: missing,
        );
        // 운행일지 알림 발행 직후, 고정알림(오늘 요약)을 재발행하여 최상단 유지
        Future.delayed(const Duration(milliseconds: 300), () {
          TodayStatsNotificationService.instance.renotifyIfEnabled();
        });
      } catch (_) {}
      ScreenshotAutoDebugLog.add('성공: DB 저장 후 완료 알림 표시');
      debugPrint('ScreenshotAutoRegister: saved successfully');
      suppressPendingRetryDueToSave = true;
    } catch (e, st) {
      ScreenshotAutoDebugLog.add('오류: $e');
      debugPrint('ScreenshotAutoRegister error: $e');
      debugPrint('$st');
    } finally {
      _busy = false;
      final pending = _pendingRetryAfterBusy;
      _pendingRetryAfterBusy = false;
      if (pending) {
        if (suppressPendingRetryDueToSave) {
          ScreenshotAutoDebugLog.add(
            '대기 이벤트 생략: 같은 캡처 버스트로 보임(방금 자동저장 성공, 불필요 재실행 방지)',
          );
        } else {
          ScreenshotAutoDebugLog.add('대기 중이던 처리 재예약(디바운스)');
          _scheduleHandle();
        }
      }
    }
  }

  /// photo_manager → 폴더 폴백 → 네이티브 MediaStore 순으로 후보 탐색.
  Future<({File? file, String? tag})> _pickScreenshotCandidate() async {
    final strict = await ScreenshotGalleryFinder.fetchLatestScreenshotFile();
    if (strict != null) return (file: strict, tag: '1순위');
    final folder = await ScreenshotGalleryFinder.fetchRecentImageFromScreenshotsFolder(
      maxAge: const Duration(seconds: 45),
    );
    if (folder != null) return (file: folder, tag: '폴더 폴백');
    final native = await _queryLatestScreenshotViaMediaStore(maxAgeSeconds: 120);
    if (native != null) return (file: native, tag: 'MediaStore 네이티브');
    return (file: null, tag: null);
  }

  /// photo_manager 에서 후보가 없을 때 네이티브 MediaStore 직접 조회(삼성 등 대응).
  Future<File?> _queryLatestScreenshotViaMediaStore({required int maxAgeSeconds}) async {
    if (!_isAndroid) return null;
    try {
      final path = await _nativeGalleryObserver.invokeMethod<String?>('queryLatestScreenshot', {
        'maxAgeSeconds': maxAgeSeconds,
      });
      if (path == null || path.isEmpty) return null;
      final f = File(path);
      if (await f.exists()) return f;
    } catch (e, st) {
      ScreenshotAutoDebugLog.add('MediaStore 네이티브 조회 실패: $e');
      debugPrint('ScreenshotAutoRegister MediaStore fallback: $e');
      debugPrint('$st');
    }
    return null;
  }

  /// 네이티브 캐시 `auto_screenshot_<id>` 는 MediaStore id 로 통합 (갤러리 경로와 이중 처리 시 경로 디바운스 일치).
  /// 파일 앞쪽 + 전체 크기 요약 해시(OCR 비용 없이 같은 그림 재저장 차단).
  Future<String?> _fileLeadingBytesSignature(File file) async {
    try {
      final len = await file.length();
      if (len <= 0) return null;
      final chunk = len > _imageSignatureMaxBytes ? _imageSignatureMaxBytes : len;
      final raf = await file.open();
      try {
        final bytes = await raf.read(chunk);
        final h = sha256.convert(bytes).toString();
        return '$len|$h';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  static String _dedupeKeyForScreenshotPath(String path) {
    final name = path.replaceAll(r'\', '/').split('/').last;
    final m = RegExp(r'^auto_screenshot_(\d+)\.').firstMatch(name);
    if (m != null) return 'media:${m.group(1)}';
    return path;
  }
}
