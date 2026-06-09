import 'package:flutter/material.dart';

/// 작성 화면 [_buildInputGroup] 과 동일한 영역 테두리 스타일.
class BorderedSection extends StatelessWidget {
  const BorderedSection({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  static BoxDecoration decoration(BuildContext context, {double borderRadius = 12}) {
    return BoxDecoration(
      color: Theme.of(context).cardTheme.color!,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: Theme.of(context).dividerColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decoration(context, borderRadius: borderRadius),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }
}
