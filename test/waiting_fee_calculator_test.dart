import 'package:flutter_test/flutter_test.dart';

import 'package:dbros_app/utils/waiting_fee_calculator.dart';

void main() {
  group('WaitingFeeCompany', () {
    test('gogo charges total minutes after 10 minutes', () {
      expect(WaitingFeeCompany.calculateFor('gogo', 10), 0);
      expect(WaitingFeeCompany.calculateFor('gogo', 11), 3300);
    });

    test('handle for you charges 10-minute blocks after grace', () {
      expect(WaitingFeeCompany.calculateFor('handle_for_you', 10), 0);
      expect(WaitingFeeCompany.calculateFor('handle_for_you', 11), 4000);
      expect(WaitingFeeCompany.calculateFor('handle_for_you', 20), 4000);
      expect(WaitingFeeCompany.calculateFor('handle_for_you', 21), 8000);
    });

    test('cheonsa uses tiered fee after grace', () {
      expect(WaitingFeeCompany.calculateFor('cheonsa', 10), 0);
      expect(WaitingFeeCompany.calculateFor('cheonsa', 34), 6000);
      expect(WaitingFeeCompany.calculateFor('cheonsa', 35), 9000);
    });

    test('daerigo adds extra blocks after 30 minutes', () {
      expect(WaitingFeeCompany.calculateFor('daerigo', 19), 0);
      expect(WaitingFeeCompany.calculateFor('daerigo', 25), 5000);
      expect(WaitingFeeCompany.calculateFor('daerigo', 31), 7000);
    });
  });
}
