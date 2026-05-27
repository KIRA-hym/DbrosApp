import 'dart:ui';
import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 프리미엄 글래스모피즘 다이얼로그.
///
/// BackdropFilter 블러 + 반투명 다크 배경 + 얇은 흰색 테두리.
/// [showDialog] 와 함께 사용하거나 [AppGlassDialog.show] 헬퍼로 띄울 수 있다.
class AppGlassDialog extends StatelessWidget {
  const AppGlassDialog({
    super.key,
    this.icon,
    this.title,
    this.titleWidget,
    this.content,
    this.contentWidget,
    this.actions = const [],
    this.contentPadding,
    this.scrollable = false,
  }) : assert(
          title != null || titleWidget != null,
          'title 또는 titleWidget 중 하나는 반드시 제공해야 합니다.',
        );

  /// 타이틀 앞에 표시할 아이콘 (선택)
  final IconData? icon;

  /// 타이틀 문자열 (titleWidget과 둘 중 하나 필수)
  final String? title;

  /// 커스텀 타이틀 위젯 (title보다 우선)
  final Widget? titleWidget;

  /// 본문 문자열 (contentWidget과 둘 다 null이면 본문 없음)
  final String? content;

  /// 커스텀 본문 위젯 (content보다 우선)
  final Widget? contentWidget;

  /// 하단 액션 버튼 목록
  final List<Widget> actions;

  /// 내부 패딩 (기본값: EdgeInsets.all(20))
  final EdgeInsetsGeometry? contentPadding;

  /// 본문이 길 경우 스크롤 허용
  final bool scrollable;

  // ─── 팩토리 헬퍼 ─────────────────────────────────────────────

  /// 간편 show 헬퍼. [showDialog]를 직접 호출하는 것과 동일.
  static Future<T?> show<T>({
    required BuildContext context,
    required AppGlassDialog dialog,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black54,
      builder: (_) => dialog,
    );
  }

  // ─── build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = contentPadding ?? const EdgeInsets.all(20);

    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: const Color(0xFFFFC700), size: 22),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: titleWidget ??
              Text(
                title!,
                style: const TextStyle(
                  fontFamily: 'GmarketSans',
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
        ),
      ],
    );

    Widget bodyContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        if (contentWidget != null || content != null) ...[
          const SizedBox(height: 14),
          if (contentWidget != null)
            contentWidget!
          else
            Text(
              content!,
              style: const TextStyle(
                color: Color(0xFFD1D2D4),
                fontSize: 14,
                height: 1.5,
              ),
            ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          _ActionsRow(actions: actions),
        ],
      ],
    );

    if (scrollable) {
      bodyContent = SingleChildScrollView(child: bodyContent);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Dialog(
          backgroundColor: const Color(0xCC1F222A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white10),
          ),
          child: Padding(
            padding: pad,
            child: bodyContent,
          ),
        ),
      ),
    );
  }
}

/// 액션 버튼 행: 버튼이 2개 이하이면 Row, 3개 이상이면 Column.
class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.length <= 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _intersperse(actions, const SizedBox(width: 8)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _intersperse(actions, const SizedBox(height: 8)),
    );
  }

  List<Widget> _intersperse(List<Widget> list, Widget separator) {
    final result = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      if (i > 0) result.add(separator);
      result.add(list[i]);
    }
    return result;
  }
}

// ─── 공용 액션 버튼 팩토리 ────────────────────────────────────────

/// 회색 취소 버튼
class GlassDialogCancelButton extends StatelessWidget {
  const GlassDialogCancelButton({
    super.key,
    required this.onPressed,
    this.label = '취소',
  });
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(color: Color(0xFF9FA3AE))),
      );
}

/// 골드(0xFFFFC700) 확인 버튼
class GlassDialogConfirmButton extends StatelessWidget {
  const GlassDialogConfirmButton({
    super.key,
    required this.onPressed,
    this.label = '확인',
    this.filled = false,
  });
  final VoidCallback onPressed;
  final String label;

  /// true이면 ElevatedButton(배경 골드), false이면 TextButton(골드 텍스트)
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFC700),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      );
    }
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold)),
    );
  }
}

/// 빨간(삭제/경고) 버튼
class GlassDialogDestructiveButton extends StatelessWidget {
  const GlassDialogDestructiveButton({
    super.key,
    required this.onPressed,
    this.label = '삭제',
  });
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.bold)),
      );
}
