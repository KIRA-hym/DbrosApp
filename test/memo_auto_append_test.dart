import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dbros_app/screens/write_log_page.dart';
import 'package:dbros_app/services/font_size_service.dart';
import 'package:dbros_app/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();
    await FontSizeService.loadFontSize();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('Automatically appends expense and extra income to memo with comma when existing memo value exists', (tester) async {
    // 1. Pump the DriveLogForm widget
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DriveLogForm(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 2. Get the element of DriveLogForm
    final BuildContext logFormElement = tester.element(find.byType(DriveLogForm));

    // 3. Pre-populate the memo with some text
    DriveLogForm.setTestMemoText(logFormElement, '킥/자전거 2.2k');
    await tester.pump();

    // 4. Input transport cost ('택틀 3k') and trigger focus changed helper
    DriveLogForm.testAppendMemoFromField(logFormElement, category: '택틀', amountStr: '3000');
    await tester.pump();

    // Verify memo has appended transport cost with comma: "킥/자전거 2.2k, 택틀 3k"
    expect(DriveLogForm.getTestMemoText(logFormElement), equals('킥/자전거 2.2k, 택틀 3k'));

    // 5. Input waypoint tip ('경유비 10k') and trigger focus changed helper
    DriveLogForm.testAppendMemoFromField(logFormElement, category: '경유비', amountStr: '10000');
    await tester.pump();

    // Verify memo has appended waypoint tip with comma: "킥/자전거 2.2k, 택틀 3k, 경유비 10k"
    expect(DriveLogForm.getTestMemoText(logFormElement), equals('킥/자전거 2.2k, 택틀 3k, 경유비 10k'));

    // 6. Test duplicate prevention: triggering again with the same value shouldn't append it again
    DriveLogForm.testAppendMemoFromField(logFormElement, category: '경유비', amountStr: '10000');
    await tester.pump();
    expect(DriveLogForm.getTestMemoText(logFormElement), equals('킥/자전거 2.2k, 택틀 3k, 경유비 10k'));
  });
}
