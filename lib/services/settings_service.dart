import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class SettingsService {
  static late SharedPreferences _prefs;
  static final ValueNotifier<bool> _showFloatingButtonsNotifier = ValueNotifier(true);
  static final ValueNotifier<bool> _isOwnerModeNotifier = ValueNotifier(false);
  static final ValueNotifier<bool> _isPremiumUserNotifier = ValueNotifier(false);

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
    _isOwnerModeNotifier.value = isOwnerMode;
    _isPremiumUserNotifier.value = isPremiumUser;
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
  static ValueNotifier<bool> get isOwnerModeNotifier => _isOwnerModeNotifier;
  static ValueNotifier<bool> get isPremiumUserNotifier => _isPremiumUserNotifier;

  static bool get isOwnerMode => _prefs.getBool('isOwnerMode') ?? false;
  static Future<void> setIsOwnerMode(bool value) async {
    await _prefs.setBool('isOwnerMode', value);
    _isOwnerModeNotifier.value = value;
  }

  static bool get isPremiumUser => _prefs.getBool('isPremiumUser') ?? false;
  static Future<void> setIsPremiumUser(bool value) async {
    await _prefs.setBool('isPremiumUser', value);
    _isPremiumUserNotifier.value = value;
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
    if (n == '티맵') return 0;

    var fee = 0;
    final isKakao = n == '카카오' || n.contains('카카오');
    if (!isKakao && n != '핸들포유') {
      fee += (grossFare * (baseFeeRate / 100)).round();
    }
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
    const withInsurance = <String>{
      '카카오(제휴)',
      '로지',
      '콜마너',
      '핸들포유',
      '기타',
    };
    return withInsurance.contains(normalizedProgram);
  }

  static List<String> get defaultProgramList => List<String>.from(_defaultProgramList);
  static List<String> get defaultExpenseList => List<String>.from(_defaultExpenseList);
  static List<String> get defaultIncomeList => List<String>.from(_defaultIncomeList);

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
  static Future<void> setIncomeList(List<String> value) async =>
      await _prefs.setStringList('incomeList', value);

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
    final expireMs = _prefs.getInt('adRewardExpireMs') ?? 0;
    if (expireMs == 0) return false;
    return DateTime.now().millisecondsSinceEpoch <= expireMs;
  }

  static Future<void> unlockFeaturesByAd() async {
    final expireMs = DateTime.now().millisecondsSinceEpoch + (3 * 60 * 60 * 1000); // 3 hours
    await _prefs.setInt('adRewardExpireMs', expireMs);
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

  static String get gasWebhookUrl => _prefs.getString('gasWebhookUrl') ?? 'https://script.google.com/macros/s/AKfycbzo6cx79n-eIZYkrd7ZJxzsCA9BC63FQ7JqFI45BInY9ES9YKjDCDI9vJRTFFwiGtvA/exec';
  static Future<void> setGasWebhookUrl(String value) async => await _prefs.setString('gasWebhookUrl', value);
}