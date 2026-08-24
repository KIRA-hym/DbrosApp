import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import '../config/feature_flags.dart';

class SettingsService {
  static late SharedPreferences _prefs;
  static Future<void> reload() async { await _prefs.reload(); }
  static final ValueNotifier<bool> _showFloatingButtonsNotifier = ValueNotifier(true);
  static final ValueNotifier<bool> _overlayQuickRegisterNotifier = ValueNotifier(false);
  static final ValueNotifier<double> _overlayButtonSizeNotifier = ValueNotifier(60.0);
  static final ValueNotifier<bool> _isOwnerModeNotifier = ValueNotifier(false);
  static final ValueNotifier<bool> _isPremiumUserNotifier = ValueNotifier(false);
  static final ValueNotifier<ThemeMode> _themeModeNotifier = ValueNotifier(ThemeMode.dark);
  static final ValueNotifier<bool> _isAmoledBlackNotifier = ValueNotifier(false);
    static final ValueNotifier<String> _addressSearchModeNotifier = ValueNotifier('both');
  static final ValueNotifier<List<String>> _noFeeProgramsNotifier = ValueNotifier([]);
  static final ValueNotifier<List<String>> _insuranceProgramsNotifier = ValueNotifier([]);
  
  static final ValueNotifier<bool> isFeatureUnlockedNotifier = ValueNotifier(false);
  static Timer? _adRewardTimer;

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

  static const List<String> _defaultExpenseList = <String>[
    '킥/자전거',
    '택틀',
    '택복',
    '식비',
    '교통',
    '기타',
  ];

  static const List<String> _defaultIncomeList = <String>[
    '경유비',
    '팁',
    '기타',
  ];

  static const List<String> _defaultMapVisibleTypes = <String>[
    'log_mine',
    'log_other',
    'shared',
    'reference',
    'restroom',
    'shuttle',
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
    await _ensureExpenseItemInList('교통', before: '기타');
    _showFloatingButtonsNotifier.value = showFloatingButtons;
    _overlayQuickRegisterNotifier.value = overlayQuickRegisterEnabled;
    _overlayButtonSizeNotifier.value = overlayButtonSize;
    _isOwnerModeNotifier.value = isOwnerMode;
    _isPremiumUserNotifier.value = isPremiumUser;
    _themeModeNotifier.value = themeMode;
    _isAmoledBlackNotifier.value = isAmoledBlack;
    _addressSearchModeNotifier.value = addressSearchMode;
    _noFeeProgramsNotifier.value = _prefs.getStringList('noFeePrograms') ?? ['카카오(일반)', '카카오(맞춤)', '카카오(프콜)', '카카오(제휴)', '티맵'];
    _insuranceProgramsNotifier.value = _prefs.getStringList('insurancePrograms') ?? ['카카오(제휴)', '로지', '콜마너', '핸들포유', '기타'];


    _startAdRewardTimer();
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

  /// 기존 지출 목록에 [item]이 없으면 [before] 항목 앞(없으면 맨 끝)에 삽입.
  static Future<void> _ensureExpenseItemInList(String item, {required String before}) async {
    final raw = _prefs.getStringList('expenseList');
    if (raw == null) return;
    final list = List<String>.from(raw);
    if (list.contains(item)) return;
    final idx = list.indexOf(before);
    if (idx >= 0) {
      list.insert(idx, item);
    } else {
      list.add(item);
    }
    await _prefs.setStringList('expenseList', list);
  }

  static ValueNotifier<bool> get showFloatingButtonsNotifier => _showFloatingButtonsNotifier;
  static ValueNotifier<bool> get overlayQuickRegisterNotifier => _overlayQuickRegisterNotifier;
  static ValueNotifier<double> get overlayButtonSizeNotifier => _overlayButtonSizeNotifier;
  static ValueNotifier<bool> get isOwnerModeNotifier => _isOwnerModeNotifier;
  static ValueNotifier<bool> get isPremiumUserNotifier => _isPremiumUserNotifier;
  static ValueNotifier<ThemeMode> get themeModeNotifier => _themeModeNotifier;
  static ValueNotifier<bool> get isAmoledBlackNotifier => _isAmoledBlackNotifier;
  static ValueNotifier<String> get addressSearchModeNotifier => _addressSearchModeNotifier;
  static ValueNotifier<List<String>> get noFeeProgramsNotifier => _noFeeProgramsNotifier;
  static ValueNotifier<List<String>> get insuranceProgramsNotifier => _insuranceProgramsNotifier;

  static ThemeMode get themeMode {
    final modeString = _prefs.getString('themeMode') ?? 'dark';
    if (modeString == 'light') return ThemeMode.light;
    return ThemeMode.dark;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final modeString = mode == ThemeMode.light ? 'light' : 'dark';
    await _prefs.setString('themeMode', modeString);
    _themeModeNotifier.value = mode;
  }

  static bool get isAmoledBlack => _prefs.getBool('isAmoledBlack') ?? false;
  static Future<void> setIsAmoledBlack(bool value) async {
    await _prefs.setBool('isAmoledBlack', value);
    _isAmoledBlackNotifier.value = value;
  }

  static String get addressSearchMode => _prefs.getString('addressSearchMode') ?? 'both';
  static Future<void> setAddressSearchMode(String value) async {
    await _prefs.setString('addressSearchMode', value);
    _addressSearchModeNotifier.value = value;
  }

  static bool get isOwnerMode => _prefs.getBool('isOwnerMode') ?? false;
  static Future<void> setIsOwnerMode(bool value) async {
    await _prefs.setBool('isOwnerMode', value);
    _isOwnerModeNotifier.value = value;
  }

  static bool get isPremiumUser => isPromoPremium || isRevenueCatPremium;

  static bool get isPromoPremium {
    final isPromo = _prefs.getBool('isPromoPremium') ?? false;
    if (!isPromo) return false;
    final expireMs = _prefs.getInt('promoExpireMs') ?? 0;
    if (expireMs == 0) return true; // 무제한
    if (DateTime.now().millisecondsSinceEpoch > expireMs) {
      _prefs.setBool('isPromoPremium', false);
      return false; // 만료됨
    }
    return true;
  }

  static Future<void> setPromoPremium(bool value, {int? durationDays}) async {
    await _prefs.setBool('isPromoPremium', value);
    if (value && durationDays != null) {
      final expireMs = DateTime.now().add(Duration(days: durationDays)).millisecondsSinceEpoch;
      await _prefs.setInt('promoExpireMs', expireMs);
    } else {
      await _prefs.remove('promoExpireMs');
    }
    _isPremiumUserNotifier.value = isPremiumUser;
    isFeatureUnlockedNotifier.value = isFeatureUnlocked();
  }

  static bool get isRevenueCatPremium => _prefs.getBool('isRevenueCatPremium') ?? false;
  static Future<void> setRevenueCatPremium(bool value) async {
    await _prefs.setBool('isRevenueCatPremium', value);
    _isPremiumUserNotifier.value = isPremiumUser;
    isFeatureUnlockedNotifier.value = isFeatureUnlocked();
  }

  static double get baseFeeRate => _prefs.getDouble('baseFeeRate') ?? 20.0;
  static Future<void> setBaseFeeRate(double value) async => await _prefs.setDouble('baseFeeRate', value);

  static String get insuranceType => _prefs.getString('insuranceType') ?? 'none';
  static Future<void> setInsuranceType(String value) async => await _prefs.setString('insuranceType', value);

  static int get perTripInsurance => _prefs.getInt('perTripInsurance') ?? 0;
  static Future<void> setPerTripInsurance(int value) async => await _prefs.setInt('perTripInsurance', value);

  static int get yearlyInsurance => _prefs.getInt('yearlyInsurance') ?? 0;
  static Future<void> setYearlyInsurance(int value) async => await _prefs.setInt('yearlyInsurance', value);

  /// DB `fee`·작성/미리보기 공통: **플랫폼 수수료율** + **건당 보험**(설정이 `per_trip`일 때).
  ///
  /// - **카카오** 전 항목(일반·프콜·맞춤·제휴·레거시 `카카오`): 플랫폼 수수료율 **적용 안 함**.
  /// - **티맵**: 항상 0.
  /// - **핸들포유**: 플랫폼 수수료율 없음; 건당 보험만 아래 집합에 해당 시 가산.
  /// - **건당 보험**이 붙는 프로그램: `카카오(제휴)`, `로지`, `콜마너`, `핸들포유`, `기타`.
  /// - **로지·콜마너·기타**: 플랫폼율 적용; 건당 보험은 위 다섯 프로그램에만.
  /// 월/년 일할 보험은 미적용.
  static int deductionFeeFromGross(int grossFare, String program) {
    final n = program.trim();
    if (n.isEmpty) return 0;
    
    // 수수료 미차감 항목에 포함되어 있으면 0 리턴
    if (noFeePrograms.contains(n)) return 0;

    var fee = 0;
    fee += (grossFare * (baseFeeRate / 100)).round();
    return fee;
  }

  /// 설정의 건당 보험료가 이 프로그램에 적용되는지 확인하고 금액 반환
  static int calculatePerTripInsurance(String program) {
    final n = program.trim();
    if (insuranceType == 'per_trip' && _perTripInsuranceAppliesToProgram(n)) {
      return perTripInsurance;
    }
    return 0;
  }

  /// 설정의 건당 보험료가 **이 프로그램**에만 반영되는지.
  static bool _perTripInsuranceAppliesToProgram(String normalizedProgram) {
    return insurancePrograms.contains(normalizedProgram.trim());
  }

  static List<String> get defaultProgramList => List<String>.from(_defaultProgramList);
    static List<String> get noFeePrograms => _noFeeProgramsNotifier.value;
  static Future<void> setNoFeeProgram(String program, bool isNoFee) async {
    final list = List<String>.from(noFeePrograms);
    if (isNoFee && !list.contains(program)) {
      list.add(program);
    } else if (!isNoFee) {
      list.remove(program);
    }
    await _prefs.setStringList('noFeePrograms', list);
    _noFeeProgramsNotifier.value = list;
  }

  static List<String> get insurancePrograms => _insuranceProgramsNotifier.value;
  static Future<void> setInsuranceProgram(String program, bool applyInsurance) async {
    final list = List<String>.from(insurancePrograms);
    if (applyInsurance && !list.contains(program)) {
      list.add(program);
    } else if (!applyInsurance) {
      list.remove(program);
    }
    await _prefs.setStringList('insurancePrograms', list);
    _insuranceProgramsNotifier.value = list;
  }

  static List<String> get defaultExpenseList => List<String>.from(_defaultExpenseList);
  static List<String> get defaultIncomeList => List<String>.from(_defaultIncomeList);

  static List<String> get mapVisibleTypes =>
      _prefs.getStringList('mapVisibleTypes') ?? List<String>.from(_defaultMapVisibleTypes);
  static Future<void> setMapVisibleTypes(List<String> value) async =>
      await _prefs.setStringList('mapVisibleTypes', value);

  static List<String> get programList =>
      _prefs.getStringList('programList') ?? defaultProgramList;
  static Future<void> setProgramList(List<String> value) async => await _prefs.setStringList('programList', value);

  static List<String> get expenseList =>
      _prefs.getStringList('expenseList') ?? defaultExpenseList;
  static Future<void> setExpenseList(List<String> value) async =>
      await _prefs.setStringList('expenseList', value);

  static Future<void> addExpenseItem(String item) async {
    final list = expenseList;
    if (!list.contains(item)) {
      list.add(item);
      await setExpenseList(list);
    }
  }

  static Future<void> removeExpenseItem(String item) async {
    final list = expenseList;
    list.remove(item);
    await setExpenseList(list);
  }

  static List<String> get incomeList =>
      _prefs.getStringList('incomeList') ?? defaultIncomeList;
  static Future<void> setIncomeList(List<String> value) async => await _prefs.setStringList('incomeList', value);

  static Future<void> addIncomeItem(String item) async {
    final list = incomeList;
    if (!list.contains(item)) {
      list.add(item);
      await setIncomeList(list);
    }
  }

  static Future<void> removeIncomeItem(String item) async {
    final list = incomeList;
    list.remove(item);
    await setIncomeList(list);
  }

  static bool get showFloatingButtons => _prefs.getBool('showFloatingButtons') ?? true;
  static Future<void> setShowFloatingButtons(bool value) async {
    await _prefs.setBool('showFloatingButtons', value);
    _showFloatingButtonsNotifier.value = value;
  }

  static bool get overlayQuickRegisterEnabled => _prefs.getBool('overlayQuickRegisterEnabled') ?? false;
  static Future<void> setOverlayQuickRegisterEnabled(bool value) async {
    await _prefs.setBool('overlayQuickRegisterEnabled', value);
    _overlayQuickRegisterNotifier.value = value;
  }

  static double get overlayButtonSize => _prefs.getDouble('overlayButtonSize') ?? 60.0;
  static Future<void> setOverlayButtonSize(double size) async {
    await _prefs.setDouble('overlayButtonSize', size);
    _overlayButtonSizeNotifier.value = size;
    try {
      await FlutterOverlayWindow.shareData({'type': 'overlay_size', 'value': size});
    } catch (_) {}
  }

  static bool get statusBarQuickEnabled {
    if (!isFeatureUnlocked()) return false;
    return _prefs.getBool('statusBarQuickEnabled') ?? false;
  }
  static Future<void> setStatusBarQuickEnabled(bool value) async =>
      await _prefs.setBool('statusBarQuickEnabled', value);

  static bool get screenshotAutoRegisterEnabled {
    if (!isFeatureUnlocked()) return false;
    return _prefs.getBool('screenshotAutoRegisterEnabled') ?? false;
  }
  static Future<void> setScreenshotAutoRegisterEnabled(bool value) async =>
      await _prefs.setBool('screenshotAutoRegisterEnabled', value);

  static bool isFeatureUnlocked() {
    if (!kMonetizationEnabled) return true;
    if (isPremiumUser) return true;
    final expireMs = _prefs.getInt('adRewardExpireMs') ?? 0;
    if (expireMs == 0) return false;
    return DateTime.now().millisecondsSinceEpoch <= expireMs;
  }

  static Future<void> unlockFeaturesByAd() async {
    final expireMs = DateTime.now().millisecondsSinceEpoch + (2 * 60 * 60 * 1000); 
    await _prefs.setInt('adRewardExpireMs', expireMs);
    _startAdRewardTimer();
  }

  static void _startAdRewardTimer() {
    _adRewardTimer?.cancel();
    if (!kMonetizationEnabled || isPremiumUser) {
      isFeatureUnlockedNotifier.value = true;
      return;
    }
    
    final expireMs = _prefs.getInt('adRewardExpireMs') ?? 0;
    if (expireMs == 0) {
      isFeatureUnlockedNotifier.value = false;
      return;
    }

    final diffMs = expireMs - DateTime.now().millisecondsSinceEpoch;
    if (diffMs <= 0) {
      _onAdRewardExpired();
    } else {
      isFeatureUnlockedNotifier.value = true;
      _adRewardTimer = Timer(Duration(milliseconds: diffMs), _onAdRewardExpired);
    }
  }

  static void _onAdRewardExpired() {
    _prefs.setInt('adRewardExpireMs', 0);
    isFeatureUnlockedNotifier.value = false;
  }
  
  static int get adRewardExpireMs => _prefs.getInt('adRewardExpireMs') ?? 0;

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

  static String get imagePurgePeriod => _prefs.getString('imagePurgePeriod') ?? 'none';
  static Future<void> setImagePurgePeriod(String value) async => await _prefs.setString('imagePurgePeriod', value);

  static bool get autoBackupEnabled => _prefs.getBool('autoBackupEnabled') ?? false;
  static Future<void> setAutoBackupEnabled(bool value) async => await _prefs.setBool('autoBackupEnabled', value);

  static String get lastAutoBackupDate => _prefs.getString('lastAutoBackupDate') ?? '';
  static Future<void> setLastAutoBackupDate(String value) async => await _prefs.setString('lastAutoBackupDate', value);

  static String get gasWebhookUrl => _prefs.getString('gasWebhookUrl') ?? 'https://script.google.com/macros/s/AKfycbwHoWtFJ_tAxEG_hMMOdYRJDb2wE7EXyG6CG8IBLD-_yH2GWIDzgELM7wDFHjglNT-H/exec';
  static Future<void> setGasWebhookUrl(String value) async => await _prefs.setString('gasWebhookUrl', value);

  static bool get hasAgreedPermissionsDisclosure => _prefs.getBool('hasAgreedPermissionsDisclosure') ?? false;
  static Future<void> setHasAgreedPermissionsDisclosure(bool value) async => await _prefs.setBool('hasAgreedPermissionsDisclosure', value);

  static bool get hasSeenOnboarding => _prefs.getBool('hasSeenOnboarding') ?? false;
  static Future<void> setHasSeenOnboarding(bool value) async => await _prefs.setBool('hasSeenOnboarding', value);

  // [원복] quickRegisterOpacity getter/setter 제거
  // 퀵등록 배경 투명도를 사용자가 직접 조절하는 기능을 추가했으나,
  // Opacity 위젯이 Scaffold 전체를 감싸면서 배경 블러 + 터치 이벤트 흡수 버그 발생.
  // 투명도는 write_log_page.dart의 backgroundColor(0xCC000000)로 하드코딩 유지.
}