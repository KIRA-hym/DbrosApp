import 'package:flutter/material.dart';

import '../utils/responsive_layout.dart';

/// 넓은 화면(폴드 펼침·태블릿)에서 본문을 읽기 좋은 최대 너비로 가운데 정렬합니다.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.fullWidth = false,
    this.maxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;

  /// 지도 등 가로 전체가 필요한 화면은 true.
  final bool fullWidth;
  final double? maxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (fullWidth) return child;

    final size = MediaQuery.sizeOf(context);
    final cap = maxWidth ?? ResponsiveLayout.contentMaxWidth(size);
    if (size.width <= cap + 1) return child;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: child,
      ),
    );
  }
}
