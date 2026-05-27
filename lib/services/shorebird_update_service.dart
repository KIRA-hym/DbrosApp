import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Shorebird OTA 패치 관리 서비스.
///
/// - Shorebird가 활성화되지 않은 디버그·일반 빌드 환경에서는 모든 예외를 무시한다.
/// - [checkAndUpdate]를 호출하면 백그라운드에서 패치 유무를 확인하고,
///   새 패치를 다운로드한다. 다운로드 완료(또는 이미 다운로드 완료 상태)이면
///   [onRestartNeeded] 스트림에 이벤트를 발행한다.
class ShorebirdUpdateService {
  ShorebirdUpdateService._();
  static final ShorebirdUpdateService instance = ShorebirdUpdateService._();

  final _updater = ShorebirdUpdater();

  final StreamController<void> _restartController =
      StreamController<void>.broadcast();

  /// 다운로드 완료 → 재시작 필요 이벤트 스트림.
  Stream<void> get onRestartNeeded => _restartController.stream;

  /// 패치 확인 및 다운로드 (백그라운드 실행).
  ///
  /// 직접 `await` 없이 `.then()`·`unawaited()` 형태로 호출하도록 설계되어 있다.
  /// 내부에서 발생하는 모든 예외는 조용히 무시한다.
  Future<void> checkAndUpdate() async {
    try {
      if (!_updater.isAvailable) {
        if (kDebugMode) debugPrint('[Shorebird] 업데이터 사용 불가 (비-Shorebird 빌드)');
        return;
      }

      final status = await _updater.checkForUpdate();
      if (kDebugMode) debugPrint('[Shorebird] 업데이트 상태: $status');

      switch (status) {
        case UpdateStatus.restartRequired:
          // 이미 패치 다운로드 완료 — 재시작만 필요
          _restartController.add(null);

        case UpdateStatus.outdated:
          // 새 패치 다운로드 시작
          if (kDebugMode) debugPrint('[Shorebird] 패치 다운로드 시작…');
          await _updater.update();
          if (kDebugMode) debugPrint('[Shorebird] 패치 다운로드 완료');
          _restartController.add(null);

        case UpdateStatus.upToDate:
        case UpdateStatus.unavailable:
          // 조치 불필요
          break;
      }
    } catch (e) {
      // Graceful degradation: Shorebird 미지원 환경에서 조용히 무시
      if (kDebugMode) debugPrint('[Shorebird] 예외 무시됨: $e');
    }
  }

  void dispose() {
    _restartController.close();
  }
}
