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
  bool _isDialogOpen = false;
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
    if (state == AppLifecycleState.resumed && _patchReady && !_isDialogOpen) {
      ShorebirdUpdateService.instance.hasPostponedUpdate().then((postponed) {
        if (!postponed && mounted && !_isDialogOpen) {
          _openDialog(PatchStage.ready);
        }
      });
    }
  }

  void _openDialog(PatchStage initialStage) {
    if (!mounted || _isDialogOpen) return;
    _isDialogOpen = true;
    ShorebirdUpdateDialog.show(context, initialStage: initialStage).whenComplete(() {
      _isDialogOpen = false;
    });
  }

  void _onPatchEvent(PatchEvent event) {
    if (!mounted) return;

    if (event.stage == PatchStage.downloading) {
      _openDialog(PatchStage.downloading);
      return;
    }

    if (event.stage == PatchStage.ready) {
      _patchReady = true;
      AutoRegisterNotificationService.instance.showShorebirdPatchReady();
      if (!_isDialogOpen) {
        _openDialog(PatchStage.ready);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}