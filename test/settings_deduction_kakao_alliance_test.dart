import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbros_app/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('카카오(제휴)만 자동 수수료, 일반·프콜·맞춤·티맵은 0', () async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    expect(SettingsService.deductionFeeFromGross(10000, '카카오(일반)'), 0);
    expect(SettingsService.deductionFeeFromGross(10000, '카카오(프콜)'), 0);
    expect(SettingsService.deductionFeeFromGross(10000, '카카오(맞춤)'), 0);
    expect(SettingsService.deductionFeeFromGross(10000, '티맵'), 0);

    final alliance = SettingsService.deductionFeeFromGross(10000, '카카오(제휴)');
    expect(alliance, (10000 * 0.2).round());
  });
}
