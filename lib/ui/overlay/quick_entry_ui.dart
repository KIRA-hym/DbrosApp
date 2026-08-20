import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../services/settings_service.dart';
import 'quick_entry_popup_form.dart';

class QuickEntryUI extends StatefulWidget {
  const QuickEntryUI({super.key});

  @override
  State<QuickEntryUI> createState() => _QuickEntryUIState();
}

class _QuickEntryUIState extends State<QuickEntryUI> {
  Offset? _webDragPosition;
  bool _showForm = false;
  bool _isTransitioning = false;
  OverlayPosition? _lastPos;

  @override
  void initState() {
    super.initState();
    SettingsService.overlayButtonSizeNotifier.addListener(_onSizeChanged);
  }

  @override
  void dispose() {
    SettingsService.overlayButtonSizeNotifier.removeListener(_onSizeChanged);
    super.dispose();
  }

  void _onSizeChanged() {
    if (!kIsWeb && mounted && !_showForm) {
      final size = SettingsService.overlayButtonSizeNotifier.value.toInt();
      FlutterOverlayWindow.resizeOverlay(size, size, true);
    }
  }

  void _onBtnTap() async {
    if (_showForm || _isTransitioning) return;
    if (kIsWeb) {
      setState(() => _showForm = true);
      return;
    }
    
    try {
      _lastPos = await FlutterOverlayWindow.getOverlayPosition();
    } catch (_) {}
    
    // 1. 즉시 트랜지션 시작 (버튼 숨김)
    setState(() => _isTransitioning = true);

    // 2. 화면에 투명 프레임이 확실히 그려질 때까지 대기 (잔상 원천 차단)
    await Future.delayed(const Duration(milliseconds: 60));

    // 3. 투명해진 상태에서 네이티브 창을 풀스크린으로 확장
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
    await FlutterOverlayWindow.resizeOverlay(WindowSize.matchParent, WindowSize.matchParent, false);
    
    // 4. 안드로이드 OS의 창 크기 확장이 완료될 때까지 대기
    await Future.delayed(const Duration(milliseconds: 200));

    // 5. 트랜지션 종료 및 폼 표시
    if (mounted) {
      setState(() {
        _isTransitioning = false;
        _showForm = true;
      });
    }
  }

  void _closeForm() async {
    if (!_showForm || _isTransitioning) return;
    if (kIsWeb) {
      setState(() => _showForm = false);
      return;
    }
    
    // 1. 트랜지션 시작 (폼 즉시 숨김)
    setState(() {
      _isTransitioning = true;
      _showForm = false;
    });

    // 2. 투명 프레임이 그려질 때까지 대기
    await Future.delayed(const Duration(milliseconds: 60));

    final size = SettingsService.overlayButtonSizeNotifier.value.toInt();
    
    // 3. 네이티브 창 축소 및 원래 위치로 이동
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    await FlutterOverlayWindow.resizeOverlay(size, size, true);
    if (_lastPos != null) {
      await FlutterOverlayWindow.moveOverlay(_lastPos!);
    }
    
    // 4. 축소 완료 대기
    await Future.delayed(const Duration(milliseconds: 200));
    
    // 5. 버튼 표시
    if (mounted) {
      setState(() {
        _isTransitioning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: SettingsService.overlayButtonSizeNotifier,
      builder: (context, overlaySize, child) {
        
        // 안드로이드 창 크기 조절 중에는 무조건 투명한 화면만 그려서 잔상 방지
        if (_isTransitioning) {
          return const Scaffold(backgroundColor: Colors.transparent);
        }
        
        if (_showForm) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: QuickEntryPopupForm(onClose: _closeForm),
          );
        }

        final size = MediaQuery.of(context).size;
        
        if (kIsWeb && _webDragPosition == null) {
          final double dx = (size.width / 2) + 160;
          final double dy = size.height - 250;
          final double maxX = (size.width - overlaySize) > 0.0 ? (size.width - overlaySize) : 0.0;
          final double maxY = (size.height - overlaySize) > 0.0 ? (size.height - overlaySize) : 0.0;
          _webDragPosition = Offset(dx.clamp(0.0, maxX), dy.clamp(0.0, maxY));
        }

        final btnInnerSize = overlaySize * 0.8;

        final btn = GestureDetector(
          onTap: _onBtnTap,
          onPanUpdate: kIsWeb
              ? (details) {
                  setState(() {
                    final screen = MediaQuery.of(context).size;
                    var newOffset = (_webDragPosition ??
                            Offset(screen.width / 2 - (btnInnerSize/2), screen.height / 2 - (btnInnerSize/2))) +
                        details.delta;
                    _webDragPosition = newOffset;
                  });
                }
              : null,
          child: Container(
            width: btnInnerSize,
            height: btnInnerSize,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFC700).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1),
              ],
              border: Border.all(color: const Color(0xFFFFC700), width: 1.5),
            ),
            child: Icon(
              Icons.edit_note,
              color: const Color(0xFFFFC700),
              size: btnInnerSize * 0.55,
            ),
          ),
        );

        if (kIsWeb) {
          final screen = MediaQuery.of(context).size;
          return Stack(
            children: [
              Positioned(
                left: _webDragPosition?.dx ?? (screen.width / 2 - (btnInnerSize/2)),
                top: _webDragPosition?.dy ?? (screen.height / 2 - (btnInnerSize/2)),
                child: btn,
              ),
            ],
          );
        }
        
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: btn),
        );
      },
    );
  }
}
