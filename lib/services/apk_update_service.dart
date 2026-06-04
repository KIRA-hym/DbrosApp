import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 정식 APK 릴리스 버전을 체크하는 서비스
class ApkUpdateService {
  ApkUpdateService._();
  static final ApkUpdateService instance = ApkUpdateService._();

  bool _hasApkUpdate = false;
  String? _downloadUrl;
  
  bool get hasApkUpdate => _hasApkUpdate;
  String? get downloadUrl => _downloadUrl;

  Future<bool> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://dbros-install.web.app/version.json'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['latest_version'] as String?;
        final downloadPath = data['download_url'] as String?;
        
        if (latestVersion != null && downloadPath != null) {
          final packageInfo = await PackageInfo.fromPlatform();
          
          final latestBuild = _parseBuildNumber(latestVersion);
          final currentBuild = _parseBuildNumber(packageInfo.buildNumber);
          
          if (kDebugMode) {
            debugPrint('[ApkUpdateService] 현재 빌드: $currentBuild, 서버 빌드: $latestBuild');
          }
          
          if (latestBuild != null && currentBuild != null && latestBuild > currentBuild) {
            _hasApkUpdate = true;
            // firebase hosting에 배포되므로 절대 경로가 아닐 경우 도메인을 붙여줌
            _downloadUrl = downloadPath.startsWith('http') 
                ? downloadPath 
                : 'https://dbros-install.web.app$downloadPath';
            return true;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ApkUpdateService] 업데이트 체크 에러: $e');
    }
    
    _hasApkUpdate = false;
    _downloadUrl = null;
    return false;
  }
  
  int? _parseBuildNumber(String buildString) {
    if (buildString.contains('+')) {
       return int.tryParse(buildString.split('+').last);
    }
    return int.tryParse(buildString);
  }
}
