/// 빌드 시 기능 토글 (구 버전 잔재, 현재는 런타임 오너 모드 여부로 동작):
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/settings_service.dart';

bool get kMapFeaturesEnabled =>
    kIsWeb || SettingsService.isOwnerMode;

/// 개인지출관리 등 오너 전용 빌드 여부 ([kMapFeaturesEnabled]와 동일 플래그).
bool get kExpenseOwnerOnly => kMapFeaturesEnabled;
