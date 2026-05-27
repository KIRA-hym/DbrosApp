/// 빌드 시 기능 토글 (구 버전 잔재, 현재는 런타임 오너 모드 여부로 동작):
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/settings_service.dart';

bool get kMapFeaturesEnabled => true;

/// 수익화(광고 및 PRO 기능) 활성화 여부
/// 베타 테스트 기간 중에는 false로 설정하여 수익화 기능을 우회합니다.
const bool kMonetizationEnabled = false;

/// 개인지출관리 등 오너 전용 빌드 여부
bool get kExpenseOwnerOnly => SettingsService.isOwnerMode;
