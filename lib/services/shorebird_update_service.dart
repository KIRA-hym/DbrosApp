import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// 패치 업데이트 단계
enum PatchStage {
  /// 새 패치 다운로드 시작됨
  downloading,

  /// 다운로드 완료 (또는 이미 완료) — 재시작하면 적용됨
  ready,
}

/// 패치 이벤트 데이터
class PatchEvent {
  const PatchEvent(this.stage, {this.patchNumber});
  final PatchStage stage;
  final int? patchNumber;
}

/// Shorebird OTA 패치 관리 서비스.
///
/// - [checkAndUpdate]를 호출하면 백그라운드에서 패치를 확인하고 다운로드한다.
/// - [patchEvents] 스트림으로 [PatchStage.downloading] → [PatchStage.ready] 이벤트를 발행한다.
/// - 동일 패치 번호에 대해서는 절대 중복 알림을 발행하지 않는다 (무한 루프 방지).
/// - 오류 발생 시 배너/다이얼로그를 표시하지 않고 조용히 종료한다.
class ShorebirdUpdateService {
  ShorebirdUpdateService._();
  static final ShorebirdUpdateService instance = ShorebirdUpdateService._();

  final _updater = ShorebirdUpdater();
  final _ctrl = StreamController<PatchEvent>.broadcast();

  static const String _prefKey = 'shorebird_notified_patch_number';

  /// 패치 진행 이벤트 스트림.
  Stream<PatchEvent> get patchEvents => _ctrl.stream;

  /// 패치 확인 및 다운로드 (백그라운드 실행).
  Future<void> checkAndUpdate() async {
    try {
      if (!_updater.isAvailable) {
        if (kDebugMode) debugPrint('[Shorebird] 업데이터 사용 불가 (비-Shorebird 빌드)');
        return;
      }

      final status = await _updater.checkForUpdate();
      if (kDebugMode) debugPrint('[Shorebird] 업데이트 상태: $status');

      switch (status) {
        case UpdateStatus.outdated:
          // 새 패치 다운로드 — UI에 진행 중 알림 먼저
          _ctrl.add(const PatchEvent(PatchStage.downloading));
          if (kDebugMode) debugPrint('[Shorebird] 패치 다운로드 시작…');
          await _updater.update();
          if (kDebugMode) debugPrint('[Shorebird] 패치 다운로드 완료');
          await _emitReadyIfNew();

        case UpdateStatus.restartRequired:
          // 이미 다운로드 완료 — 중복 알림 없이 ready 이벤트만
          await _emitReadyIfNew();

        case UpdateStatus.upToDate:
        case UpdateStatus.unavailable:
          break;
      }
    } catch (e) {
      // 어떤 예외도 배너/다이얼로그를 띄우지 않음
      if (kDebugMode) debugPrint('[Shorebird] 예외 무시됨: $e');
    }
  }

  /// 이미 알림한 패치인지 확인 후 새 패치일 때만 [PatchStage.ready] 이벤트 발행.
  ///
  /// - null/예외 → 조용히 반환 (배너 없음). 루프 방지 핵심 로직.
  Future<void> _emitReadyIfNew() async {
    try {
      final patch = await _updater.readNextPatch();
      final patchNumber = patch?.number;

      // 패치 번호를 읽을 수 없으면 아무것도 하지 않음 (배너 표시 안 함)
      if (patchNumber == null) {
        if (kDebugMode) debugPrint('[Shorebird] readNextPatch null — 알림 생략');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final notified = prefs.getInt(_prefKey);

      if (notified == patchNumber) {
        if (kDebugMode) debugPrint('[Shorebird] 패치 #$patchNumber 이미 알림됨 — 건너뜀');
        return;
      }

      // 새 패치: 번호 저장 후 이벤트 발행
      await prefs.setInt(_prefKey, patchNumber);
      if (kDebugMode) debugPrint('[Shorebird] 패치 #$patchNumber ready 이벤트 발행');
      _ctrl.add(PatchEvent(PatchStage.ready, patchNumber: patchNumber));
    } catch (e) {
      // 읽기 실패 시 배너를 표시하지 않음 (루프 방지)
      if (kDebugMode) debugPrint('[Shorebird] _emitReadyIfNew 오류, 알림 생략: $e');
    }
  }

  void dispose() => _ctrl.close();
}
