import 'dart:async';

import 'package:flutter/material.dart';

import '../services/shorebird_update_service.dart';
import '../services/apk_update_service.dart';
import '../services/auto_register_notification_service.dart';
import 'shorebird_update_dialog.dart';
import 'apk_update_dialog.dart';

class ShorebirdUpdateHost extends StatefulWidget {
  const ShorebirdUpdateHost({super.key, required this.child});
  final Widget child;

  @override
  State<ShorebirdUpdateHost> createState() => _ShorebirdUpdateHostState();
}

class _ShorebirdUpdateHostState extends State<ShorebirdUpdateHost> with WidgetsBindingObserver {
  StreamSubscription<PatchEvent>? _sub;
  bool _dialogShown = false;
  bool _patchReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = ShorebirdUpdateService.instance.patchEvents.listen(_onPatchEvent);
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hasApk = await ApkUpdateService.instance.checkForUpdate();
      if (hasApk && mounted) {
        ApkUpdateDialog.show(
          context, 
          ApkUpdateService.instance.downloadUrl ?? 'https://dbros-install.web.app/'
        );
      } else {
        ShorebirdUpdateService.instance.checkAndUpdate();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _patchReady && !_dialogShown) {
      _dialogShown = true;
      ShorebirdUpdateDialog.show(context);
    }
  }

  void _onPatchEvent(PatchEvent event) {
    if (!mounted) return;

    if (event.stage == PatchStage.ready) {
      _patchReady = true;
      AutoRegisterNotificationService.instance.showShorebirdPatchReady();
      // 만약 이미 앱 화면을 보고 있다면 3초 뒤에 자연스럽게 팝업 표시
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_dialogShown) {
          _dialogShown = true;
          ShorebirdUpdateDialog.show(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}