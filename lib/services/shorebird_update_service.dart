import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// 패치 업데이트 단계
enum PatchStage {
  /// 새 패치 다운로드 시작됨
  downloading,

  /// 다운로드 완료 — 재시작하면 적용됨
  ready,

  /// 다운로드 중 오류 발생
  error,
}

/// 패치 이벤트 데이터
class PatchEvent {
  const PatchEvent(this.stage, {this.patchNumber});
  final PatchStage stage;
  final int? patchNumber;
}

/// Shorebird OTA 패치 관리 서비스.
class ShorebirdUpdateService {
  ShorebirdUpdateService._();
  static final ShorebirdUpdateService instance = ShorebirdUpdateService._();

  final _updater = ShorebirdUpdater();
  final _ctrl = StreamController<PatchEvent>.broadcast();

  static const String _prefNotifiedPatch = 'shorebird_notified_patch_number';
  static const String _prefPendingPatch = 'shorebird_pending_patch_number';
  static const String _prefAppliedPatch = 'shorebird_applied_patch_number';
  static const String _prefPostponedPatch = 'shorebird_postponed_patch_number';

  Stream<PatchEvent> get patchEvents => _ctrl.stream;

  Future<bool> hasPostponedUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final postponed = prefs.getInt(_prefPostponedPatch);
    final pending = prefs.getInt(_prefPendingPatch);
    return postponed != null && postponed == pending;
  }

  Future<void> postponeUpdate(int patchNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefPostponedPatch, patchNumber);
  }

  /// 현재·대기 패치 번호 (설정 화면 디버그용)
  Future<({int? current, int? pending, bool available})> getPatchInfo() async {
    if (!_updater.isAvailable) {
      return (current: null, pending: null, available: false);
    }
    try {
      final current = await _updater.readCurrentPatch();
      final next = await _updater.readNextPatch();
      final prefs = await SharedPreferences.getInstance();
      final pendingStored = prefs.getInt(_prefPendingPatch);
      return (
        current: current?.number,
        pending: next?.number ?? pendingStored,
        available: true,
      );
    } catch (_) {
      return (current: null, pending: null, available: true);
    }
  }

  Future<bool> checkAndUpdate() async {
    try {
      if (!_updater.isAvailable) {
        if (kDebugMode) debugPrint('[Shorebird] 업데이터 사용 불가');
        return false;
      }

      await _syncAppliedPatchState();

      final status = await _updater.checkForUpdate();
      if (kDebugMode) debugPrint('[Shorebird] 상태: $status');

      switch (status) {
        case UpdateStatus.outdated:
          _ctrl.add(const PatchEvent(PatchStage.downloading));
          if (kDebugMode) debugPrint('[Shorebird] 다운로드 시작');
          await _updater.update();
          await _storePendingPatchNumber();
          if (kDebugMode) debugPrint('[Shorebird] 다운로드 완료');
          await _emitReadyIfNew(forceEmit: true);
          return true;

        case UpdateStatus.restartRequired:
          await _emitReadyIfNew();
          return true;

        case UpdateStatus.upToDate:
          await _clearPendingIfApplied();
          return false;

        case UpdateStatus.unavailable:
          return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Shorebird] 예외: $e');
      _ctrl.add(const PatchEvent(PatchStage.error));
    }
    return false;
  }

  /// 재시작 후 패치가 적용됐으면 pending·알림 상태를 정리한다.
  Future<void> _syncAppliedPatchState() async {
    try {
      final current = await _updater.readCurrentPatch();
      if (current == null) return;

      final prefs = await SharedPreferences.getInstance();
      final lastApplied = prefs.getInt(_prefAppliedPatch) ?? 0;

      if (current.number > lastApplied) {
        if (kDebugMode) {
          debugPrint('[Shorebird] 패치 적용됨: #$lastApplied → #${current.number}');
        }
        await prefs.setInt(_prefAppliedPatch, current.number);
        await prefs.setInt(_prefNotifiedPatch, current.number);
        await prefs.remove(_prefPendingPatch);
        await prefs.remove(_prefPostponedPatch);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Shorebird] syncApplied 오류: $e');
    }
  }

  Future<void> _clearPendingIfApplied() async {
    try {
      final current = await _updater.readCurrentPatch();
      final next = await _updater.readNextPatch();
      if (current == null || next == null) return;
      if (current.number == next.number) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefPendingPatch);
      }
    } catch (_) {}
  }

  Future<void> _storePendingPatchNumber() async {
    try {
      final next = await _updater.readNextPatch();
      if (next == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefPendingPatch, next.number);
      if (kDebugMode) debugPrint('[Shorebird] pending 저장: #${next.number}');
    } catch (_) {}
  }

  Future<void> _emitReadyIfNew({bool forceEmit = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await _updater.readCurrentPatch();
      final next = await _updater.readNextPatch();
      final pendingStored = prefs.getInt(_prefPendingPatch);

      // 대기 중 패치 번호: readNextPatch → SharedPreferences 순으로 확인
      final pendingNumber = next?.number ?? pendingStored;

      if (kDebugMode) {
        debugPrint(
          '[Shorebird] current=#${current?.number} next=#${next?.number} '
          'stored=#$pendingStored → pending=#$pendingNumber',
        );
      }

      if (pendingNumber == null) {
        if (kDebugMode) debugPrint('[Shorebird] pending 없음 — 다이얼로그 생략');
        if (forceEmit) {
          // update()가 예외 없이 성공했으나 플러그인이 아직 다음 패치 번호를 반환하지 못하는 경우
          // 업데이트 자체는 다운로드 완료된 상태이므로 성공(ready) 이벤트를 발생시킵니다.
          _ctrl.add(const PatchEvent(PatchStage.ready));
        }
        return;
      }

      // 이미 적용된 패치와 같으면 알림 불필요
      if (current?.number == pendingNumber) {
        await prefs.remove(_prefPendingPatch);
        if (forceEmit) _ctrl.add(const PatchEvent(PatchStage.error));
        return;
      }

      final notified = prefs.getInt(_prefNotifiedPatch);
      if (notified == pendingNumber && !forceEmit) {
        if (kDebugMode) debugPrint('[Shorebird] #$pendingNumber 이미 알림함');
        return;
      }

      await prefs.setInt(_prefNotifiedPatch, pendingNumber);
      _ctrl.add(PatchEvent(PatchStage.ready, patchNumber: pendingNumber));
      if (kDebugMode) debugPrint('[Shorebird] ready 이벤트 #$pendingNumber');
    } catch (e) {
      if (kDebugMode) debugPrint('[Shorebird] emitReady 오류: $e');
      if (forceEmit) _ctrl.add(const PatchEvent(PatchStage.error));
    }
  }

  void dispose() => _ctrl.close();
}
