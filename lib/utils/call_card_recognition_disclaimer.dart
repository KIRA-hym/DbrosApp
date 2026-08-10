import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_glass_dialog.dart';

/// 콜카드 인식(기존 OCR) 이용 안내 팝업을 표시하고 동의를 받는다.
/// 한 번 동의한 사용자는 SharedPreferences 에 기록되어 다시 보지 않는다.
///
/// Returns:
///   true: 동의함 (또는 이미 동의한 상태)
///   false: 거절함 (또는 모달 바깥 터치로 취소됨)
Future<bool> ensureCallCardRecognitionDisclaimer(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final hasSeen = prefs.getBool('has_seen_ocr_disclaimer') ?? false;
  if (hasSeen) return true;

  if (!context.mounted) return false;

  bool? accepted = await AppGlassDialog.show<bool>(
    context: context,
    dialog: AppGlassDialog(
      title: "콜카드 인식 이용 안내",
      icon: Icons.info_outline,
      contentWidget: const Text(
        "콜카드 인식 기능은 콜카드 이미지를 읽어 문구를 자동 입력하는 기능입니다.\n\n"
        "100% 완벽하지 않을 수 있으며, 화면 화질이나 폰트 설정 등에 따라 간혹 잘못된 값이 입력될 수 있습니다.\n\n"
        "자동 입력된 금액과 출발/도착지 등이 올바른지 저장 전 반드시 한 번 더 확인해 주세요.",
        style: TextStyle(fontSize: 14, height: 1.4, color: Colors.white70),
      ),
      actions: [
        Builder(
          builder: (ctx) => GlassDialogCancelButton(
            label: '취소',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ),
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.15),
              foregroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('동의 및 계속', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    ),
  );

  if (accepted == true) {
    await prefs.setBool('has_seen_ocr_disclaimer', true);
    return true;
  }
  return false;
}
