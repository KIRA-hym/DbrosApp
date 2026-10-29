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
  PatchStage _currentStage = PatchStage.ready;
  PatchStage get currentStage => _currentStage;
  bool _isChecking = false;
  Timer? _nativeWatcherTimer;
  int? _postponedInSessionPatch;

  void _emitEvent(PatchEvent event) {
    _currentStage = event.stage;
    _ctrl.add(event);
  }

  static const String _prefNotifiedPatch = 'shorebird_notified_patch_number';
  static const String _prefPendingPatch = 'shorebird_pending_patch_number';
  static const String _prefAppliedPatch = 'shorebird_applied_patch_number';
  static const String _prefPostponedPatch = 'shorebird_postponed_patch_number';

  Stream<PatchEvent> get patchEvents => _ctrl.stream;

  Future<bool> hasPostponedUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final postponed = prefs.getInt(_prefPostponedPatch);
    final notified = prefs.getInt(_prefNotifiedPatch);
    final pending = prefs.getInt(_prefPendingPatch);
    if (pending == null) return false;
    return postponed == pending ||
        notified == pending ||
        _postponedInSessionPatch == pending;
  }

  Future<void> postponeUpdate(int patchNumber) async {
    _postponedInSessionPatch = patchNumber;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefPostponedPatch, patchNumber);
    await prefs.setInt(_prefNotifiedPatch, patchNumber);
  }

  /// 디스크에 현재 실행 중인 패치와 다른 새 패치(nextPatch)가 실제로 준비되어 있는지 검증 (100% Ground Truth)
  Future<({bool ready, int? nextNumber, int? currentNumber})> checkDiskPatchState() async {
    if (!_updater.isAvailable) {
      return (ready: false, nextNumber: null, currentNumber: null);
    }
    try {
      final current = await _updater.readCurrentPatch();
      final next = await _updater.readNextPatch();
      final isReady = next != null && next.number != current?.number;
      return (
        ready: isReady,
        nextNumber: next?.number,
        currentNumber: current?.number,
      );
    } catch (_) {
      return (ready: false, nextNumber: null, currentNumber: null);
    }
  }

  Future<bool> isPatchReadyToApply() async {
    final state = await checkDiskPatchState();
    return state.ready;
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
    if (!_updater.isAvailable) return false;
    if (_isChecking) return false;
    _isChecking = true;

    try {
      await _syncAppliedPatchState();

      // 1) 이미 네이티브 auto_update 등이 패치를 다운로드해 둔 상태인지 디스크부터 즉시 확인
      final initialDisk = await checkDiskPatchState();
      if (initialDisk.ready) {
        await _storePendingPatchNumber(initialDisk.nextNumber);
        await _emitReadyIfNew(forceEmit: false);
        return true;
      }

      // 2) 네이티브 백그라운드 auto_update가 몇 초 뒤 완료되는 케이스를 잡기 위한 워처 가동
      _startNativeAutoUpdateWatchers();

      UpdateStatus status = UpdateStatus.upToDate;
      try {
        status = await _updater.checkForUpdate().timeout(const Duration(seconds: 8));
      } catch (e) {
        if (kDebugMode) debugPrint('[Shorebird] checkForUpdate 예외 (네이티브 다운로드 중일 수 있음): $e');
        // checkForUpdate 실패 시에도 잠시 후 디스크에 패치가 들어왔는지 확인
        await Future.delayed(const Duration(seconds: 2));
        final retryDisk = await checkDiskPatchState();
        if (retryDisk.ready) {
          await _storePendingPatchNumber(retryDisk.nextNumber);
          await _emitReadyIfNew(forceEmit: false);
          return true;
        }
        return false;
      }

      if (status == UpdateStatus.outdated) {
        _emitEvent(const PatchEvent(PatchStage.downloading));

        // Dart update() 호출 (네이티브 auto_update와 락이 겹쳐 예외가 나더라도 폴링으로 완료 추적)
        bool updateCallFinished = false;
        unawaited(() async {
          for (int i = 0; i < 2; i++) {
            try {
              await _updater.update().timeout(const Duration(seconds: 20));
              updateCallFinished = true;
              break;
            } catch (e) {
              if (kDebugMode) debugPrint('[Shorebird] update() 예외 (폴링으로 대기 계속): $e');
              await Future.delayed(const Duration(seconds: 1));
              final disk = await checkDiskPatchState();
              if (disk.ready) {
                updateCallFinished = true;
                break;
              }
            }
          }
        }());

        // 최대 15초 동안 1초 간격으로 실제 디스크에 nextPatch가 준비되었는지 검증
        bool readyOnDisk = false;
        int? readyPatchNumber;
        for (int sec = 0; sec < 15; sec++) {
          await Future.delayed(const Duration(seconds: 1));
          final disk = await checkDiskPatchState();
          if (disk.ready) {
            readyOnDisk = true;
            readyPatchNumber = disk.nextNumber;
            break;
          }
          if (updateCallFinished) {
            // update() 호출이 정상 종료되었다면 한 번 더 확인 후 탈출
            final afterCallDisk = await checkDiskPatchState();
            if (afterCallDisk.ready) {
              readyOnDisk = true;
              readyPatchNumber = afterCallDisk.nextNumber;
            }
            break;
          }
        }

        if (readyOnDisk || updateCallFinished) {
          await _storePendingPatchNumber(readyPatchNumber);
          await _emitReadyIfNew(forceEmit: true);
        } else {
          // 15초 내 다운로드 미완료 시 에러 이벤트를 보내 다이얼로그가 무한 루프에 갇히지 않게 보장
          _emitEvent(const PatchEvent(PatchStage.error));
        }
        return true;
      } else if (status == UpdateStatus.restartRequired) {
        final disk = await checkDiskPatchState();
        await _storePendingPatchNumber(disk.nextNumber);
        await _emitReadyIfNew(forceEmit: false);
        return true;
      } else if (status == UpdateStatus.upToDate) {
        // 서버 기준 upToDate라도 로컬에 아직 안내하지 않은 nextPatch가 있으면 1회 팝업 노출
        final disk = await checkDiskPatchState();
        if (disk.ready) {
          await _storePendingPatchNumber(disk.nextNumber);
          await _emitReadyIfNew(forceEmit: false);
          return true;
        }
        await _clearPendingIfApplied();
      }
    } catch (_) {
    } finally {
      _isChecking = false;
    }
    return false;
  }

  void _startNativeAutoUpdateWatchers() {
    _nativeWatcherTimer?.cancel();
    int checks = 0;
    _nativeWatcherTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      checks++;
      if (checks > 4) {
        timer.cancel();
        return;
      }
      if (_isChecking) return;
      final disk = await checkDiskPatchState();
      if (disk.ready) {
        timer.cancel();
        await _storePendingPatchNumber(disk.nextNumber);
        await _emitReadyIfNew(forceEmit: false);
      }
    });
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

  Future<void> _storePendingPatchNumber([int? knownNextNumber]) async {
    try {
      final nextNum = knownNextNumber ?? (await _updater.readNextPatch())?.number;
      if (nextNum == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefPendingPatch, nextNum);
      if (kDebugMode) debugPrint('[Shorebird] pending 저장: #$nextNum');
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
        return;
      }

      // 이미 적용된 패치와 같으면 알림 불필요
      if (current?.number == pendingNumber) {
        await prefs.remove(_prefPendingPatch);
        return;
      }

      final notified = prefs.getInt(_prefNotifiedPatch);
      final postponed = prefs.getInt(_prefPostponedPatch);

      // 이미 안내했거나 사용자가 '지금 재시작' 또는 '나중에 하기'를 누른 패치 번호면 중복 팝업 절대 금지
      if (!forceEmit &&
          (notified == pendingNumber ||
              postponed == pendingNumber ||
              _postponedInSessionPatch == pendingNumber)) {
        if (kDebugMode) {
          debugPrint('[Shorebird] 이미 안내/처리된 패치 #$pendingNumber — 중복 팝업 생략');
        }
        return;
      }

      await prefs.setInt(_prefNotifiedPatch, pendingNumber);
      _emitEvent(PatchEvent(PatchStage.ready, patchNumber: pendingNumber));
      if (kDebugMode) debugPrint('[Shorebird] ready 이벤트 #$pendingNumber');
    } catch (e) {
      if (kDebugMode) debugPrint('[Shorebird] emitReady 오류: $e');
    }
  }

  void dispose() => _ctrl.close();
}

