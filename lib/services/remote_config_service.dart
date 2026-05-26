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
}
