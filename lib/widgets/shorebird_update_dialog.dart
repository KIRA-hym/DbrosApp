import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

import '../services/shorebird_update_service.dart';

/// Shorebird 패치 업데이트 다이얼로그.
///
/// 다운로드 단계와 완료 단계를 하나의 다이얼로그에서 처리한다.
/// - [PatchStage.downloading]: 스피너 + "다운로드 중" 표시
/// - [PatchStage.ready]: 완료 아이콘 + "확인" 버튼 표시 → 확인 시 앱 재시작
class ShorebirdUpdateDialog extends StatefulWidget {
  const ShorebirdUpdateDialog({
    super.key,
    required this.initialStage,
  });

  final PatchStage initialStage;

  /// 다이얼로그 표시. [stageNotifier]를 반환하여 외부에서 단계를 업데이트할 수 있다.
  static ValueNotifier<PatchStage> show(
    BuildContext context,
    PatchStage initialStage,
  ) {
    final notifier = ValueNotifier(initialStage);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _ShorebirdUpdateDialogBody(stageNotifier: notifier),
    );
    return notifier;
  }
}

class _ShorebirdUpdateDialogBody extends StatefulWidget {
  const _ShorebirdUpdateDialogBody({required this.stageNotifier});
  final ValueNotifier<PatchStage> stageNotifier;

  @override
  State<_ShorebirdUpdateDialogBody> createState() =>
      _ShorebirdUpdateDialogBodyState();
}

class _ShorebirdUpdateDialogBodyState
    extends State<_ShorebirdUpdateDialogBody>
    with TickerProviderStateMixin {
  late PatchStage _stage;
  late AnimationController _checkController;
  late Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _stage = widget.stageNotifier.value;
    widget.stageNotifier.addListener(_onStageChanged);

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );

    if (_stage == PatchStage.ready) {
      _checkController.forward();
    }
  }

  @override
  void dispose() {
    widget.stageNotifier.removeListener(_onStageChanged);
    _checkController.dispose();
    super.dispose();
  }

  void _onStageChanged() {
    if (!mounted) return;
    setState(() {
      _stage = widget.stageNotifier.value;
    });
    if (_stage == PatchStage.ready) {
      _checkController.forward();
    }
  }

  void _onConfirm() {
    Navigator.of(context).pop();
    Restart.restartApp();
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
                _buildIcon(),
                const SizedBox(height: 20),
                _buildTexts(),
                const SizedBox(height: 24),
                _buildBottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (_stage == PatchStage.downloading) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFFFFC700).withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: Color(0xFFFFC700),
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    // ready 단계: 체크 아이콘 (탄성 애니메이션)
    return ScaleTransition(
      scale: _checkScale,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF4CAF50),
          size: 36,
        ),
      ),
    );
  }

  Widget _buildTexts() {
    final title = _stage == PatchStage.downloading
        ? '업데이트 다운로드 중'
        : '업데이트 준비 완료';

    final subtitle = _stage == PatchStage.downloading
        ? '최신 패치를 다운로드하는 중입니다.\n잠시만 기다려주세요...'
        : '새 패치가 준비되었습니다.\n확인을 누르면 앱이 재시작되며\n업데이트가 자동으로 적용됩니다.';

    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'GmarketSans',
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFFB0B3BB),
            fontSize: 13,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBottom() {
    if (_stage == PatchStage.downloading) {
      // 다운로드 중: 인디케이터바 표시
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              backgroundColor: Color(0xFF2A2D3A),
              color: Color(0xFFFFC700),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '백그라운드에서 자동 다운로드 중...',
            style: TextStyle(color: Color(0xFF7A7D8A), fontSize: 11),
          ),
        ],
      );
    }

    // 준비 완료: 확인 버튼
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _onConfirm,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFFC700),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          '확인 (앱 재시작)',
          style: TextStyle(
            fontFamily: 'GmarketSans',
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
