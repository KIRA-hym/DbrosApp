import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// OCR 프로그램 인식 실패 시 전체 텍스트를 클립보드로 복사할 수 있게 안내한다.
class OcrFailureFeedback {
  OcrFailureFeedback._();

  static Future<bool> copyFullText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    await Clipboard.setData(ClipboardData(text: trimmed));
    return true;
  }

  static void showUnrecognizedSnackbar(
    BuildContext context, {
    String message = '인식불가한 이미지입니다.',
    required String fullText,
    String actionLabel = 'OCR 복사',
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final hasText = fullText.trim().isNotEmpty;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: hasText
            ? SnackBarAction(
                label: actionLabel,
                onPressed: () {
                  copyFullText(fullText).then((ok) {
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? 'OCR 텍스트를 복사했습니다.' : '복사할 OCR 텍스트가 없습니다.',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  });
                },
              )
            : null,
      ),
    );
  }
}
