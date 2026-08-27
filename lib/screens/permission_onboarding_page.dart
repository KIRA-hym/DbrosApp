import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionOnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const PermissionOnboardingPage({Key? key, required this.onComplete}) : super(key: key);

  @override
  State<PermissionOnboardingPage> createState() => _PermissionOnboardingPageState();
}

class _PermissionOnboardingPageState extends State<PermissionOnboardingPage> {
  bool _isRequesting = false;

  Future<void> _requestPermissions() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
    });

    if (!kIsWeb && Platform.isAndroid) {
      // 1. 일반 권한 일괄 요청 (알림, 마이크, 사진, 위치)
      List<Permission> permissionsToRequest = [
        Permission.notification,
        Permission.microphone,
        Permission.location,
        Permission.photos,
        Permission.storage,
      ];

      await permissionsToRequest.request();

      // 2. 오버레이(다른 앱 위에 표시) 권한 확인 및 요청
      if (!await Permission.systemAlertWindow.isGranted) {
        await Permission.systemAlertWindow.request();
      }
    }

    // 온보딩 완료 처리
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_permission_onboarding', true);

    if (mounted) {
      widget.onComplete();
    }
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required Color iconColor,
    required String name,
    required bool isRequired,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isRequired ? Colors.blue.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isRequired ? '필수' : '선택',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isRequired ? Colors.blue : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                '운행일지관리앱을 사용하기위해\n권한 허용이 필요해요.',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '원활한 일지등록을 위해\n아래 권한들을 설정해주세요.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade400,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildPermissionItem(
                      icon: Icons.notifications_active,
                      iconColor: Colors.amber.shade400,
                      name: '알림',
                      isRequired: true,
                      description: '상태바 고정알림 (순익표시)',
                    ),
                    _buildPermissionItem(
                      icon: Icons.mic,
                      iconColor: Colors.blue,
                      name: '마이크',
                      isRequired: true,
                      description: '음성인식 주소입력',
                    ),
                    _buildPermissionItem(
                      icon: Icons.folder,
                      iconColor: Colors.green,
                      name: '사진 및 동영상',
                      isRequired: true,
                      description: '콜카드 캡쳐 스크린샷 자동 인식 및 저장',
                    ),
                    _buildPermissionItem(
                      icon: Icons.location_on,
                      iconColor: Colors.redAccent,
                      name: '위치',
                      isRequired: false,
                      description: '내 위치 기반 콜포인트 지도 표시',
                    ),
                    _buildPermissionItem(
                      icon: Icons.layers,
                      iconColor: Colors.purpleAccent,
                      name: '다른 앱 위에 표시',
                      isRequired: false,
                      description: '퀵등록 플로팅 버튼 표시',
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isRequesting ? null : _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade400,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          '확인하고 시작하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
