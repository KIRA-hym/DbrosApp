import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbros_app/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('카카오 전 항목: 플랫폼 수수료 0 (건당 보험 off)', () async {
    SharedPreferences.setMockInitialValues({'insuranceType': 'none'});
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '카카오(일반)'), 0);
    expect(SettingsService.deductionFeeFromGross(10000, '카카오(프콜)'), 0);
    expect(SettingsService.deductionFeeFromGross(10000, '카카오(맞춤)'), 0);
    expect(SettingsService.deductionFeeFromGross(10000, '카카오(제휴)'), 0);
    expect(SettingsService.deductionFeeFromGross(10000, '카카오'), 0);
  });

  test('카카오(일반): 건당 보험 on 이어도 보험 가산 없음', () async {
    SharedPreferences.setMockInitialValues({
      'insuranceType': 'per_trip',
      'perTripInsurance': 500,
    });
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '카카오(일반)'), 0);
  });

  test('카카오(제휴): 건당 보험만 (플랫폼 0)', () async {
    SharedPreferences.setMockInitialValues({
      'insuranceType': 'per_trip',
      'perTripInsurance': 500,
    });
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '카카오(제휴)'), 500);
  });

  test('로지·콜마너: 플랫폼% + 건당 보험', () async {
    SharedPreferences.setMockInitialValues({
      'insuranceType': 'per_trip',
      'perTripInsurance': 300,
      'baseFeeRate': 20.0,
    });
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '로지'), 2000 + 300);
    expect(SettingsService.deductionFeeFromGross(10000, '콜마너'), 2000 + 300);
  });

  test('핸들포유: 플랫폼 0, 건당 보험만', () async {
    SharedPreferences.setMockInitialValues({
      'insuranceType': 'per_trip',
      'perTripInsurance': 400,
    });
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '핸들포유'), 400);
  });

  test('기타: 플랫폼%만 (건당 보험 대상 아님)', () async {
    SharedPreferences.setMockInitialValues({
      'insuranceType': 'per_trip',
      'perTripInsurance': 999,
      'baseFeeRate': 20.0,
    });
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '기타'), 2000);
  });

  test('티맵: 항상 0', () async {
    SharedPreferences.setMockInitialValues({
      'insuranceType': 'per_trip',
      'perTripInsurance': 999,
    });
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '티맵'), 0);
  });
}
