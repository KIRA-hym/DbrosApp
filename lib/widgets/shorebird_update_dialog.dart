import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:restart_app/restart_app.dart';

import '../services/shorebird_update_service.dart';

/// Shorebird 패치 업데이트 완료 시 띄우는 다이얼로그.
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
    
    _checkController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
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
    // 부드러운 앱 재시작
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
                _buildBottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
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
    return const Column(
      children: [
        Text(
          '업데이트 준비 완료',
          style: TextStyle(
            fontFamily: 'GmarketSans',
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 10),
        Text(
          '새로운 패치가 준비되었습니다.\n지금 앱을 재시작하여 바로 적용하시겠습니까?',
          style: TextStyle(
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
