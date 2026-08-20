import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/font_size_service.dart';

class CsInquiryPage extends StatefulWidget {
  const CsInquiryPage({super.key});

  @override
  State<CsInquiryPage> createState() => _CsInquiryPageState();
}

class _CsInquiryPageState extends State<CsInquiryPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isLoading = false;

  // TODO: 대표님의 구글 계정으로 Apps Script를 생성한 뒤 발급받은 URL로 변경해주세요.
  static const String _webhookUrl = 'https://script.google.com/macros/s/AKfycbzPxzIGNuSzGLaiqIiTDBUm_9F2hqKKXveFo4_0ICJJ41qfQXwD5OB7H5xbsuFsUM-MDA/exec';

  Future<void> _submitInquiry() async {
    if (_titleController.text.trim().isEmpty || _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 모두 입력해주세요.'), backgroundColor: Color(0xFFFF5252)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = context.read<AuthService>().user;
      final email = user?.email ?? '이메일 없음';

      // 1. 기기 정보 및 앱 버전 수집
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      
      String deviceInfo = '알 수 없는 기기';
      final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfoPlugin.androidInfo;
        deviceInfo = 'Android ${androidInfo.version.release} (${androidInfo.model})';
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfoPlugin.iosInfo;
        deviceInfo = 'iOS ${iosInfo.systemVersion} (${iosInfo.utsname.machine})';
      }

      // 2. 발송 데이터 구성
      final payload = {
        'email': email,
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'deviceInfo': deviceInfo,
        'appVersion': appVersion,
      };

      // 3. 구글 앱스 스크립트로 전송
      final response = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      // 응답 코드가 200 또는 302(리다이렉트)일 경우 성공으로 간주
      if (response.statusCode == 200 || response.statusCode == 302) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('문의가 성공적으로 접수되었습니다.\n담당자가 확인 후 답변 드리겠습니다.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        Navigator.pop(context);
      } else {
        throw Exception('전송 실패 (상태 코드: ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('문의 접수에 실패했습니다: $e'),
          backgroundColor: const Color(0xFFFF5252),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('고객지원 (이메일 문의)'),
        backgroundColor: Theme.of(context).cardTheme.color,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '이용 중 불편하신 점이나 건의사항을 남겨주시면, 회원님의 이메일로 빠르게 답변해 드립니다.',
                style: TextStyle(
                  color: const Color(0xFF9FA3AE),
                  fontSize: FontSizeService.getScaledFontSize(14),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '문의 제목',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '제목을 입력해주세요',
                  hintStyle: const TextStyle(color: Color(0xFF6E717C)),
                  filled: true,
                  fillColor: const Color(0xFF1A1D24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '문의 내용',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                maxLines: 8,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '오류가 발생한 경우, 최대한 자세한 상황을 적어주시면 문제 해결에 큰 도움이 됩니다.\n\n(참고: 정확한 원인 분석을 위해 현재 스마트폰 기종과 앱 버전 정보가 함께 전송됩니다.)',
                  hintStyle: const TextStyle(color: Color(0xFF6E717C), height: 1.5),
                  filled: true,
                  fillColor: const Color(0xFF1A1D24),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitInquiry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC700),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 3),
                      )
                    : Text(
                        '문의 보내기',
                        style: TextStyle(
                          fontSize: FontSizeService.getScaledFontSize(16),
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
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
