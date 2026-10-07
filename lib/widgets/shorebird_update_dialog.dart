import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:restart_app/restart_app.dart';

import '../services/shorebird_update_service.dart';

/// Shorebird 패치 상태를 보여주는 다이얼로그.
abstract final class ShorebirdUpdateDialog {
  static void show(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const _ShorebirdUpdateDialogBody(),
    );
  }
}

class _ShorebirdUpdateDialogBody extends StatefulWidget {
  const _ShorebirdUpdateDialogBody();

  @override
  State<_ShorebirdUpdateDialogBody> createState() =>
      _ShorebirdUpdateDialogBodyState();
}

class _ShorebirdUpdateDialogBodyState
    extends State<_ShorebirdUpdateDialogBody>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late Animation<double> _checkScale;
  
  StreamSubscription<PatchEvent>? _sub;
  PatchStage _currentStage = PatchStage.downloading;

  @override
  void initState() {
    super.initState();

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    
    // 현재 상태 가져오기
    _sub = ShorebirdUpdateService.instance.patchEvents.listen((event) {
      if (!mounted) return;
      setState(() {
        _currentStage = event.stage;
      });
      if (event.stage == PatchStage.ready || event.stage == PatchStage.error) {
        _checkController.forward();
      }
    });
  }

  @override
  void dispose() {
    _checkController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    Navigator.of(context).pop();
    // 재시작 전 오버레이(Foreground Service)를 먼저 정리한다.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }
      } catch (_) {}
    }
    Restart.restartApp();
  }

  Future<void> _onPostpone() async {
    final info = await ShorebirdUpdateService.instance.getPatchInfo();
    if (info.pending != null) {
      await ShorebirdUpdateService.instance.postponeUpdate(info.pending!);
    }
    if (!mounted) return;
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
                _buildIcon(),
                const SizedBox(height: 20),
                _buildTexts(),
                const SizedBox(height: 24),
                if (_currentStage == PatchStage.downloading)
                  const SizedBox(height: 96) // Reserve space for buttons so dialog doesn't jump
                else
                  _buildBottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (_currentStage == PatchStage.downloading) {
      return Container(
        width: 64,
        height: 64,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const CircularProgressIndicator(
          color: Color(0xFF3B82F6),
          strokeWidth: 3,
        ),
      );
    }
    
    final isError = _currentStage == PatchStage.error;
    final color = isError ? const Color(0xFFEF4444) : const Color(0xFF4CAF50);
    final icon = isError ? Icons.error_outline_rounded : Icons.check_circle_rounded;

    return ScaleTransition(
      scale: _checkScale,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 36,
        ),
      ),
    );
  }

  Widget _buildTexts() {
    String title = '업데이트 준비 완료';
    String desc = '새로운 패치가 준비되었습니다.\\n지금 앱을 재시작하여 바로 적용하시겠습니까?';

    if (_currentStage == PatchStage.downloading) {
      title = '업데이트 다운로드 중';
      desc = '새로운 패치를 다운로드하고 있습니다.\\n잠시만 기다려 주세요...';
    } else if (_currentStage == PatchStage.error) {
      title = '업데이트 실패';
      desc = '패치 다운로드 중 오류가 발생했습니다.\\n나중에 다시 시도해주세요.';
    }

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
          desc.replaceAll('\\n', '\n'),
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
    if (_currentStage == PatchStage.error) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4A4D55),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
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
              '지금 재시작',
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
            onPressed: _onPostpone,
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
    );
  }
}
