import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontSizeService {
  static const String _fontSizeKey = 'fontSize';
  static const double _defaultFontSize = 1.0;
  static const double _minFontSize = 0.5;
  static const double _maxFontSize = 2.0;
  static const double _stepSize = 0.1;

  static double _currentFontSize = _defaultFontSize;
  static final _notifier = ValueNotifier<double>(_defaultFontSize);

  static ValueNotifier<double> get fontNotifier => _notifier;

  static double get currentFontSize => _currentFontSize;

  static Future<void> loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    _currentFontSize = prefs.getDouble(_fontSizeKey) ?? _defaultFontSize;
    _notifier.value = _currentFontSize;
  }

  static Future<void> setFontSize(double fontSize) async {
    if (fontSize < _minFontSize || fontSize > _maxFontSize) return;
    
    _currentFontSize = fontSize;
    _notifier.value = fontSize;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, fontSize);
  }

  static Future<void> increaseFontSize() async {
    final newSize = _currentFontSize + _stepSize;
    if (newSize <= _maxFontSize) {
      await setFontSize(newSize);
    }
  }

  /// 화면 해상도(가로/세로 짧은 축) 기준으로 안전한 최대 폰트 배율.
  /// 과도한 확대 시 텍스트 오버플로우/레이아웃 깨짐을 줄이기 위한 상한.
  static double adaptiveMaxScaleForScreen(Size size) {
    final shortest = size.shortestSide;
    if (shortest < 360) return 1.2;
    if (shortest < 400) return 1.3;
    if (shortest < 480) return 1.45;
    if (shortest < 600) return 1.6;
    return _maxFontSize;
  }

  /// 현재 기기 해상도에서 실제로 적용 가능한 폰트 배율.
  static double effectiveFontScale(MediaQueryData mq) {
    final maxAdaptive = adaptiveMaxScaleForScreen(mq.size);
    return _currentFontSize.clamp(_minFontSize, maxAdaptive);
  }

  /// 해상도별 상한을 고려한 확대.
  static Future<void> increaseFontSizeForMediaQuery(MediaQueryData mq) async {
    final maxAdaptive = adaptiveMaxScaleForScreen(mq.size);
    final next = (_currentFontSize + _stepSize).clamp(_minFontSize, maxAdaptive);
    if (next != _currentFontSize) {
      await setFontSize(next);
    }
  }

  static Future<void> decreaseFontSize() async {
    final newSize = _currentFontSize - _stepSize;
    if (newSize >= _minFontSize) {
      await setFontSize(newSize);
    }
  }

  static Future<void> resetFontSize() async {
    await setFontSize(_defaultFontSize);
  }

  static TextStyle getScaledTextStyle(TextStyle originalStyle) {
    return originalStyle.copyWith(
      fontSize: (originalStyle.fontSize ?? 14),
    );
  }

  /// 테마 등에 넣는 논리 크기(px). 실제 표시 크기는 [combinedTextScaler] 배율이 추가로 적용됩니다.
  static double getScaledFontSize(double originalSize) => originalSize;

  /// 시스템 접근성 배율과 사용자 폰트 설정을 곱한 스케일러.
  static TextScaler combinedTextScaler(MediaQueryData mq) {
    final systemLinear = mq.textScaler.scale(100.0) / 100.0;
    return TextScaler.linear(systemLinear * effectiveFontScale(mq));
  }
}
