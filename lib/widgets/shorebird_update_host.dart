import 'dart:async';

import 'package:flutter/material.dart';

import '../services/shorebird_update_service.dart';
import '../services/apk_update_service.dart';
import 'shorebird_update_dialog.dart';
import 'apk_update_dialog.dart';

/// 앱 루트에서 Shorebird 패치 이벤트를 구독하고 업데이트 다이얼로그를 표시한다.
///
/// [HomePage]가 아닌 [MainWrapper]에 두어 탭·화면과 무관하게 동작하게 한다.
class ShorebirdUpdateHost extends StatefulWidget {
  const ShorebirdUpdateHost({super.key, required this.child});

  final Widget child;

  @override
  State<ShorebirdUpdateHost> createState() => _ShorebirdUpdateHostState();
}

class _ShorebirdUpdateHostState extends State<ShorebirdUpdateHost> {
  StreamSubscription<PatchEvent>? _sub;
  ValueNotifier<PatchStage>? _stageNotifier;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _sub = ShorebirdUpdateService.instance.patchEvents.listen(_onPatchEvent);
    // 첫 프레임 이후 컨텍스트가 준비된 뒤 패치 확인
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
    _sub?.cancel();
    _stageNotifier?.dispose();
    super.dispose();
  }

  void _onPatchEvent(PatchEvent event) {
    if (!mounted) return;

    if (event.stage == PatchStage.downloading) {
      if (_dialogShown) return;
      _dialogShown = true;
      _stageNotifier = ShorebirdUpdateDialog.show(context, PatchStage.downloading);
      return;
    }

    if (event.stage == PatchStage.ready) {
      if (_dialogShown && _stageNotifier != null) {
        _stageNotifier!.value = PatchStage.ready;
      } else if (!_dialogShown) {
        _dialogShown = true;
        _stageNotifier = ShorebirdUpdateDialog.show(context, PatchStage.ready);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
