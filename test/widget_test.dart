import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dbros_app/main.dart';
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

  testWidgets('DbrosApp builds with shell and copyright footer', (tester) async {
    await tester.pumpWidget(const DbrosApp());
    await tester.pump();

    expect(find.textContaining('Copyright 2026 Dbros'), findsOneWidget);
  });
}
