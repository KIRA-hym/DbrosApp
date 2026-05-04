/// 빌드 시 기능 토글:
/// - owner(지도·개인지출 등): --dart-define=MAP_FEATURES_ENABLED=true
/// - public(지도·개인지출 비활성): --dart-define=MAP_FEATURES_ENABLED=false
const bool kMapFeaturesEnabled =
    bool.fromEnvironment('MAP_FEATURES_ENABLED', defaultValue: true);

/// 개인지출관리 등 오너 전용 빌드 여부 ([kMapFeaturesEnabled]와 동일 플래그).
const bool kExpenseOwnerOnly = kMapFeaturesEnabled;
