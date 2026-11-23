import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/work_date_utils.dart';

/// 기기 로컬 시계(날짜/시간) 조작으로 광고 보상/일일 횟수 제한을 우회하는 것을 방지하기 위한
/// 무료 HTTP Date 헤더 + 단조 시계(Stopwatch) + 영구 High-Water Mark 기반 신뢰 시계 서비스.
///
/// - 별도 서버/Firestore 과금 없이 공용 204 엔드포인트의 HTTP `Date` 헤더만 사용.
/// - 동기화 후에는 단조 시계(Stopwatch) 경과시간을 더해 기기 시계 변경에 영향을 받지 않음.
/// - 오프라인 상태에서도 이전에 기록된 최대 시각(High-Water Mark) 아래로 되감기 불가.
class TrustedClockService {
  TrustedClockService._();

  static const String _highWaterKey = 'trusted_clock_high_water_ms';
  static const Duration _resyncInterval = Duration(minutes: 5);
  static const Duration _httpTimeout = Duration(seconds: 3);

  static SharedPreferences? _prefs;
  static final Stopwatch _stopwatch = Stopwatch();

  static bool _isServerSynced = false;
  static int _serverAnchorUtcMs = 0;
  static int _stopwatchAnchorMs = 0;
  static int _lastSyncedElapsedMs = -999999999;
  static int _highWaterMs = 0;
  static Future<bool>? _syncInFlight;

  @visibleForTesting
  static DateTime Function()? nowOverride;

  /// 초기화 (SharedPreferences 및 단조 시계 시작)
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
    _highWaterMs = _prefs?.getInt(_highWaterKey) ?? 0;
    final localMs = DateTime.now().millisecondsSinceEpoch;
    if (_highWaterMs == 0) {
      _highWaterMs = localMs;
      await _prefs?.setInt(_highWaterKey, _highWaterMs);
    }
  }

  /// 현재 신뢰 시각 반환 (서버 동기화 완료 시 단조 시계 기반, 미동기화 시 High-Water Mark 보정)
  static DateTime now() {
    final override = nowOverride;
    if (override != null) {
      return override();
    }

    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }

    if (_isServerSynced) {
      final elapsed = _stopwatch.elapsedMilliseconds - _stopwatchAnchorMs;
      final trustedMs = _serverAnchorUtcMs + (elapsed < 0 ? 0 : elapsed);
      if (trustedMs > _highWaterMs) {
        _highWaterMs = trustedMs;
      }
      return DateTime.fromMillisecondsSinceEpoch(trustedMs);
    }

    final localMs = DateTime.now().millisecondsSinceEpoch;
    if (localMs < _highWaterMs) {
      // 오프라인 상태에서 기기 시계를 과거로 되돌린 경우 High-Water Mark 유지
      return DateTime.fromMillisecondsSinceEpoch(_highWaterMs);
    }
    if (localMs > _highWaterMs) {
      _highWaterMs = localMs;
    }
    return DateTime.fromMillisecondsSinceEpoch(localMs);
  }

  static int nowMs() => now().millisecondsSinceEpoch;

  /// 신뢰 시각 기준 근무일(오전 9시 경계) YYYY-MM-DD
  static String effectiveWorkDateYmd() =>
      WorkDateUtils.effectiveWorkDateYmd(now());

  static bool get isServerSynced => _isServerSynced;

  /// 현재 신뢰 시각을 High-Water Mark로 영구 저장
  static Future<void> persistHighWater() async {
    if (nowOverride != null) return;
    final currentMs = nowMs();
    if (currentMs > _highWaterMs) {
      _highWaterMs = currentMs;
    }
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.setInt(_highWaterKey, _highWaterMs);
    } catch (_) {}
  }

  /// 무료 공용 엔드포인트 HTTP `Date` 헤더로 신뢰 시각 동기화 (비용 0원)
  static Future<bool> syncWithServer({bool force = false}) async {
    if (nowOverride != null || kIsWeb) return false;
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }

    final nowElapsed = _stopwatch.elapsedMilliseconds;
    if (!force &&
        _isServerSynced &&
        (nowElapsed - _lastSyncedElapsedMs) < _resyncInterval.inMilliseconds) {
      return true;
    }

    if (_syncInFlight != null) {
      return _syncInFlight!;
    }

    final future = _performSync();
    _syncInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_syncInFlight, future)) {
        _syncInFlight = null;
      }
    }
  }

  static Future<bool> _performSync() async {
    const endpoints = <String>[
      'https://clients3.google.com/generate_204',
      'https://www.google.com/generate_204',
    ];

    for (final url in endpoints) {
      try {
        final response = await http.head(Uri.parse(url)).timeout(_httpTimeout);
        final dateHeader = response.headers['date'];
        if (dateHeader == null || dateHeader.trim().isEmpty) continue;

        final parsedUtc = HttpDate.parse(dateHeader.trim());
        final serverMs = parsedUtc.millisecondsSinceEpoch;
        final elapsedNow = _stopwatch.elapsedMilliseconds;

        _serverAnchorUtcMs = serverMs;
        _stopwatchAnchorMs = elapsedNow;
        _lastSyncedElapsedMs = elapsedNow;
        _isServerSynced = true;
        // 서버 시각 확인 시 High-Water Mark를 정확한 서버 시각으로 교정
        _highWaterMs = serverMs;

        try {
          final prefs = _prefs ?? await SharedPreferences.getInstance();
          _prefs = prefs;
          await prefs.setInt(_highWaterKey, _highWaterMs);
        } catch (_) {}
        return true;
      } catch (_) {
        // 다음 폴백 엔드포인트 시도
      }
    }
    return false;
  }

  /// 테스트 전용: 서버 동기화 상태 시뮬레이션
  @visibleForTesting
  static void setServerAnchorForTest(int serverUtcMs) {
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
    _serverAnchorUtcMs = serverUtcMs;
    _stopwatchAnchorMs = _stopwatch.elapsedMilliseconds;
    _lastSyncedElapsedMs = _stopwatchAnchorMs;
    _isServerSynced = true;
    _highWaterMs = serverUtcMs;
  }

  @visibleForTesting
  static void resetForTest() {
    nowOverride = null;
    _prefs = null;
    _isServerSynced = false;
    _serverAnchorUtcMs = 0;
    _stopwatchAnchorMs = 0;
    _lastSyncedElapsedMs = -999999999;
    _highWaterMs = 0;
    _syncInFlight = null;
  }
}
