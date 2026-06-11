import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class PermissionDisclosureDialog extends StatelessWidget {
  const PermissionDisclosureDialog({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    if (!SettingsService.hasAgreedPermissionsDisclosure) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PermissionDisclosureDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Theme.of(context).cardTheme.color!,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.privacy_tip, color: const Color(0xFFFFC700)),
                  const SizedBox(width: 8),
                  Text(
                    '[필수 권한 안내]',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFFC700),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "'Dbros 운행일지관리' 앱은 다음과 같은 기능을 위해 아래 권한을 필요로 합니다.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                    ),
              ),
              const SizedBox(height: 20),
              _buildPermissionItem(
                context,
                icon: Icons.layers,
                title: '1. 다른 앱 위에 표시 (오버레이)',
                description: '사용자가 운행 중 배차 프로그램 화면 위에서 즉시 일지를 등록할 수 있도록 퀵 패널을 띄우기 위해 사용됩니다.',
              ),
              const SizedBox(height: 16),
              _buildPermissionItem(
                context,
                icon: Icons.image_search,
                title: '2. 미디어/저장소 접근 (스크린샷 감지)',
                description: '백그라운드 환경에서 배차 화면의 캡처(스크린샷) 이벤트가 발생했을 때, 이를 즉각 감지하여 자동으로 운행 일지 정보를 판독 및 등록하기 위해 사용됩니다. 앱을 닫거나 사용하지 않을 때도 이 기능이 동작합니다.',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "당사 앱은 운행 시간, 출발지 주소, 도착지 주소, 운행 요금 등 단순 운행 관련 정보만 판독하며, 어떠한 개인정보(PII)도 수집하거나 판독하지 않습니다.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.redAccent,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await SettingsService.setHasAgreedPermissionsDisclosure(true);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    '동의하고 시작하기',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem(BuildContext context, {required IconData icon, required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.7) ?? Colors.white70, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.8) ?? Colors.white70,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
