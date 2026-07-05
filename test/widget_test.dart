import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:week_schedule/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpReadyApp(WidgetTester tester) async {
    await tester.pumpWidget(const WeekScheduleApp());
    await tester.pumpAndSettle();
  }

  testWidgets('starts directly on the weekly timetable', (tester) async {
    await pumpReadyApp(tester);

    expect(find.byKey(const ValueKey('app-logo')), findsNothing);
    expect(find.text('주간'), findsOneWidget);
    expect(find.text('월간'), findsOneWidget);
    expect(find.text('문화이론과 대중문화'), findsWidgets);
  });

  testWidgets('shows the weekly timetable with view toggle', (tester) async {
    await pumpReadyApp(tester);

    // 주간/월간 전환 버튼이 모두 보인다.
    expect(find.text('주간'), findsOneWidget);
    expect(find.text('월간'), findsOneWidget);
    // 고정 시간표 시드 일정이 주간 그리드에 나타난다.
    expect(find.text('문화이론과 대중문화'), findsWidgets);
  });

  testWidgets('switches to the month view', (tester) async {
    await pumpReadyApp(tester);

    await tester.tap(find.text('월간'));
    await tester.pumpAndSettle();

    // 월간 달력의 요일 헤더(일~토)가 표시된다.
    expect(find.text('일'), findsWidgets);
    expect(find.text('토'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds a fixed schedule from the form sheet', (tester) async {
    await pumpReadyApp(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 유형 선택(고정/일회성)과 제목 입력이 모두 노출된다.
    expect(find.text('고정 (매주 반복)'), findsOneWidget);
    expect(find.text('일회성'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '디자인 회의');
    const weekdayLabels = {
      DateTime.monday: '월',
      DateTime.tuesday: '화',
      DateTime.wednesday: '수',
      DateTime.thursday: '목',
      DateTime.friday: '금',
      DateTime.saturday: '토',
      DateTime.sunday: '일',
    };
    final extraWeekday =
        DateTime.now().weekday == DateTime.wednesday
            ? DateTime.thursday
            : DateTime.wednesday;
    await tester.tap(
      find.widgetWithText(FilterChip, weekdayLabels[extraWeekday]!),
    );
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('디자인 회의'), findsAtLeastNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpReadyApp(tester);

    expect(find.text('디자인 회의'), findsAtLeastNWidgets(2));
  });

  testWidgets('lays out on mobile and desktop widths', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await pumpReadyApp(tester);

      expect(find.text('주간'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await pumpAt(const Size(390, 844));
    await pumpAt(const Size(1200, 900));
  });
}
