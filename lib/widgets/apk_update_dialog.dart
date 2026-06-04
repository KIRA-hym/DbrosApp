import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// APK 신규 버전 업데이트 안내 다이얼로그
abstract final class ApkUpdateDialog {
  static void show(BuildContext context, String downloadUrl) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _ApkUpdateDialogBody(downloadUrl: downloadUrl),
    );
  }
}

class _ApkUpdateDialogBody extends StatelessWidget {
  const _ApkUpdateDialogBody({required this.downloadUrl});
  final String downloadUrl;

  Future<void> _onConfirm(BuildContext context) async {
    Navigator.of(context).pop();
    final url = Uri.parse(downloadUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _onPostpone(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D27).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update,
                    color: Color(0xFF2196F3),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '새로운 앱 버전 출시',
                  style: TextStyle(
                    fontFamily: 'GmarketSans',
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  '최신 정식 버전(APK)이 출시되었습니다.\n안정적이고 원활한 서비스 이용을 위해\n지금 바로 다운로드하여 설치해 주세요!',
                  style: TextStyle(
                    color: Color(0xFFB0B3BB),
                    fontSize: 13,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _onConfirm(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '업데이트 다운로드',
                      style: TextStyle(
                        fontFamily: 'GmarketSans',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => _onPostpone(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7A7D8A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '나중에 하기',
                      style: TextStyle(
                        fontFamily: 'GmarketSans',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
