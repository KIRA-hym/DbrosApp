/// 빌드 시 기능 토글:
/// - owner(지도 포함): --dart-define=MAP_FEATURES_ENABLED=true
/// - public(지도 제외): --dart-define=MAP_FEATURES_ENABLED=false
const bool kMapFeaturesEnabled =
    bool.fromEnvironment('MAP_FEATURES_ENABLED', defaultValue: true);
