import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();

  factory RemoteConfigService() => _instance;

  RemoteConfigService._internal();

  FirebaseRemoteConfig? get _remoteConfig {
    try {
      if (kIsWeb) return null;
      return FirebaseRemoteConfig.instance;
    } catch (_) {
      return null;
    }
  }

  // 기본 정규식 (오프라인 상태거나 최초 다운로드 전일 때 사용)
  static const String _defaultTmapRegex = 
      r'^[o0•*·\-\s]*(?:(?:서울|경기|인천|강원|충북|충남|전북|전남|경북|경남|세종|제주|부산|대구|광주|대전|울산)[가-힣]*(?:\s+|$)|[가-힣]{1,5}(?:시|도|군|구)(?:\s+|$))';
  
  static const String _defaultRegionRegex = 
      r'(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)';

  static const String _defaultKakaoRegex = 
      r'^(출발지|도착지|위치|경유지|출발|도착|추천가)\s*';

  Future<void> initialize() async {
    final rc = _remoteConfig;
    if (rc == null) return;
    try {
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1), 
      ));

      await rc.setDefaults(const {
        'tmap_address_pattern': _defaultTmapRegex,
        'region_pattern': _defaultRegionRegex,
        'kakao_address_pattern': _defaultKakaoRegex,
        'app_notice_message': '',
      });

      await rc.fetchAndActivate();
    } catch (e) {
      if (kDebugMode) {
        print('Remote Config fetch failed: $e');
      }
    }
  }

  Future<bool> forceFetch() async {
    final rc = _remoteConfig;
    if (rc == null) return false;
    try {
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero,
      ));
      return await rc.fetchAndActivate();
    } catch (e) {
      if (kDebugMode) {
        print('Remote Config force fetch failed: $e');
      }
      return false;
    }
  }

  String get tmapAddressPattern {
    final rc = _remoteConfig;
    if (rc == null) return _defaultTmapRegex;
    final pattern = rc.getString('tmap_address_pattern');
    return pattern.isEmpty ? _defaultTmapRegex : pattern;
  }

  String get regionPattern {
    final rc = _remoteConfig;
    if (rc == null) return _defaultRegionRegex;
    final pattern = rc.getString('region_pattern');
    return pattern.isEmpty ? _defaultRegionRegex : pattern;
  }

  String get kakaoAddressPattern {
    final rc = _remoteConfig;
    if (rc == null) return _defaultKakaoRegex;
    final pattern = rc.getString('kakao_address_pattern');
    return pattern.isEmpty ? _defaultKakaoRegex : pattern;
  }

  String get appNoticeMessage {
    final rc = _remoteConfig;
    if (rc == null) {
      if (kIsWeb) {
        return '[테스트 공지] 웹 프리뷰 환경입니다. 실제 앱에서는 파이어베이스 Remote Config에서 설정한 내용이 여기에 표시됩니다.';
      }
      return '';
    }
    return rc.getString('app_notice_message');
  }

  // ── SmartOcrService / GeminiOcrService 관련 ──────────────────────────────

  /// Google AI Studio에서 발급한 Gemini API Key.
  /// Firebase Remote Config 'gemini_api_key' 키로 관리 (앱 업데이트 없이 변경 가능).
  String get geminiApiKey {
    final rc = _remoteConfig;
    if (rc == null) return '';
    return rc.getString('gemini_api_key');
  }

  /// 하루 최대 Gemini API 호출 허용 횟수 (기본값 1400 = 무료 티어 내).
  /// Firebase Remote Config 'gemini_daily_limit' 키로 관리.
  /// 0으로 설정하면 Gemini 완전 비활성화.
  int get geminiDailyLimit {
    final rc = _remoteConfig;
    if (rc == null) return 1400;
    final val = rc.getInt('gemini_daily_limit');
    return val > 0 ? val : 1400;
  }

  /// OCR 결과 주소에 포함되면 가비지로 판단하는 단어 목록.
  /// Firebase Remote Config 'ocr_forbidden_words' 키로 관리 (쉼표 구분 문자열).
  List<String> get ocrForbiddenWords {
    final rc = _remoteConfig;
    const defaults = ['상황실', '기사메모', '연락처', '킥보드', '대여시간', '고객메모', '취소불가'];
    if (rc == null) return defaults;
    final raw = rc.getString('ocr_forbidden_words');
    if (raw.isEmpty) return defaults;
    return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// OCR 주소 최대 허용 글자 수. 초과 시 가비지로 판단.
  /// Firebase Remote Config 'ocr_max_address_length' 키로 관리.
  int get ocrMaxAddressLength {
    final rc = _remoteConfig;
    if (rc == null) return 25;
    final val = rc.getInt('ocr_max_address_length');
    return val > 0 ? val : 25;
  }
}
