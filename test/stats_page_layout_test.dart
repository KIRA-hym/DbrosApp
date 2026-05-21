import 'package:dbros_app/screens/stats_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('StatsPage renders on wide viewport (web-like)', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('운행 일지 통계'), findsOneWidget);
    expect(find.text('전체 통계'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatsPage renders on narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('운행 일지 통계'), findsOneWidget);
    expect(find.text('프로그램별 매출'), findsOneWidget);
    expect(find.text('시간대별 순수익'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stat cards fit in short viewport without layout overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('총 순수익'), findsOneWidget);
    expect(find.text('총 매출'), findsOneWidget);
    expect(find.text('총 지출'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folded layout stacks charts vertically', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final programTitle = find.text('프로그램별 매출');
    final hourlyTitle = find.text('시간대별 순수익');
    expect(programTitle, findsOneWidget);
    expect(hourlyTitle, findsOneWidget);

    final programBox = tester.getRect(programTitle);
    final hourlyBox = tester.getRect(hourlyTitle);
    expect(programBox.bottom, lessThan(hourlyBox.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded layout places charts in a horizontal row', (tester) async {
    // Z Fold 펼침 세로에 가까운 단말기 크기
    tester.view.physicalSize = const Size(690, 830);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final programTitle = find.text('프로그램별 매출');
    final hourlyTitle = find.text('시간대별 순수익');
    final programBox = tester.getRect(programTitle);
    final hourlyBox = tester.getRect(hourlyTitle);
    expect(programBox.right, lessThan(hourlyBox.left));
    expect(find.byIcon(Icons.chevron_left), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
