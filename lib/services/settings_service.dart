import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class SettingsService {
  static late SharedPreferences _prefs;
  static final ValueNotifier<bool> _showFloatingButtonsNotifier = ValueNotifier(true);
  static const List<String> _defaultProgramList = <String>[
    '카카오(일반)',
    '카카오(맞춤)',
    '카카오(프콜)',
    '카카오(제휴)',
    '로지',
    '콜마너',
    '티맵',
    '핸들포유',
    '기타',
  ];

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // 월/년 일할 보험은 UI·로직에서 제거됨. 기존 'monthly' 선택은 'none'으로 이전.
    if (_prefs.getString('insuranceType') == 'monthly') {
      await _prefs.setString('insuranceType', 'none');
    }
    const legacyDefault = <String>['카카오', '로지', '콜마너', '티맵', '핸들포유', '기타'];
    final savedPrograms = _prefs.getStringList('programList');
    if (savedPrograms == null ||
        listEquals(savedPrograms, legacyDefault)) {
      await _prefs.setStringList('programList', defaultProgramList);
    }
    await _ensureAllianceProgramInList();
    _showFloatingButtonsNotifier.value = showFloatingButtons;
  }

  /// 기존 저장 목록에 `카카오(제휴)`가 없으면 카카오 항목 근처에 삽입.
  static Future<void> _ensureAllianceProgramInList() async {
    const alliance = '카카오(제휴)';
    final raw = _prefs.getStringList('programList');
    if (raw == null) return;
    final list = List<String>.from(raw);
    if (list.contains(alliance)) return;
    final pro = list.indexOf('카카오(프콜)');
    if (pro >= 0) {
      list.insert(pro + 1, alliance);
    } else {
      final custom = list.indexOf('카카오(맞춤)');
      if (custom >= 0) {
        list.insert(custom + 1, alliance);
      } else {
        final gen = list.indexOf('카카오(일반)');
        if (gen >= 0) {
          list.insert(gen + 1, alliance);
        } else {
          list.insert(0, alliance);
        }
      }
    }
    await _prefs.setStringList('programList', list);
  }

  static ValueNotifier<bool> get showFloatingButtonsNotifier => _showFloatingButtonsNotifier;

  static double get baseFeeRate => _prefs.getDouble('baseFeeRate') ?? 20.0;
  static Future<void> setBaseFeeRate(double value) async => await _prefs.setDouble('baseFeeRate', value);

  static String get insuranceType => _prefs.getString('insuranceType') ?? 'none';
  static Future<void> setInsuranceType(String value) async => await _prefs.setString('insuranceType', value);

  static int get perTripInsurance => _prefs.getInt('perTripInsurance') ?? 0;
  static Future<void> setPerTripInsurance(int value) async => await _prefs.setInt('perTripInsurance', value);

  static int get yearlyInsurance => _prefs.getInt('yearlyInsurance') ?? 0;
  static Future<void> setYearlyInsurance(int value) async => await _prefs.setInt('yearlyInsurance', value);

  /// DB `fee`·작성/미리보기 공통: 수수료율 + 건당 보험.
  /// 카카오(일반·프콜·맞춤)·티맵·핸들포유는 플랫폼 차감 제외로 **0**. `카카오(제휴)`만 차감.
  /// 월/년 일할 보험은 추후 구현; 미적용.
  static int deductionFeeFromGross(int grossFare, String program) {
    if (isAutoDeductionExcludedProgram(program)) return 0;
    int fee = (grossFare * (baseFeeRate / 100)).round();
    if (insuranceType == 'per_trip') {
      fee += perTripInsurance;
    }
    return fee;
  }

  static const Set<String> _kakaoProgramsExcludedFromDeduction = {
    '카카오',
    '카카오(일반)',
    '카카오(프콜)',
    '카카오(맞춤)',
  };

  static bool isAutoDeductionExcludedProgram(String program) {
    final normalized = program.trim();
    if (normalized.isEmpty) return false;
    if (_kakaoProgramsExcludedFromDeduction.contains(normalized)) return true;
    return normalized == '티맵' || normalized == '핸들포유';
  }

  static List<String> get defaultProgramList => List<String>.from(_defaultProgramList);

  static List<String> get programList =>
      _prefs.getStringList('programList') ?? defaultProgramList;
  static Future<void> setProgramList(List<String> value) async => await _prefs.setStringList('programList', value);

  static bool get showFloatingButtons => _prefs.getBool('showFloatingButtons') ?? true;
  static Future<void> setShowFloatingButtons(bool value) async {
    await _prefs.setBool('showFloatingButtons', value);
    _showFloatingButtonsNotifier.value = value;
  }

  /// 상태바 고정 알림 + 이후 퀵 기능 마스터 (Android 중심).
  static bool get statusBarQuickEnabled => _prefs.getBool('statusBarQuickEnabled') ?? false;
  static Future<void> setStatusBarQuickEnabled(bool value) async =>
      await _prefs.setBool('statusBarQuickEnabled', value);

  static Future<void> addProgram(String program) async {
    final currentList = programList;
    if (!currentList.contains(program)) {
      currentList.add(program);
      await setProgramList(currentList);
    }
  }
  
  static Future<void> removeProgram(String program) async {
    final currentList = programList;
    currentList.remove(program);
    await setProgramList(currentList);
  }
}