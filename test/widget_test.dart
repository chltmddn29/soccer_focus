import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_planner/main.dart';

void main() {
  testWidgets('선수 선택은 한 명만 유지되고 해당 경기 정보를 표시한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    expect(find.text('축구선수 포커스'), findsOneWidget);

    final expectedRecords = [
      ['8.4 km', '2골', '1개', '32회'],
      ['10.2 km', '0골', '2개', '68회'],
      ['7.6 km', '0골', '0개', '45회'],
    ];
    for (var index = 0; index < players.length; index++) {
      final player = players[index];
      final chip = find.widgetWithText(
        ChoiceChip,
        '${player.name} · ${player.position}',
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text('선택 선수: ${player.name}'), findsOneWidget);
      final selected = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .where((chip) => chip.selected);
      expect(selected.length, 1);
      for (final record in expectedRecords[index]) {
        expect(find.text(record), findsOneWidget);
      }
    }

    // 이미 선택한 선수를 다시 눌러도 선택을 해제하지 않습니다.
    await tester.tap(find.widgetWithText(ChoiceChip, '어떤이 · 수비수'));
    await tester.pumpAndSettle();
    expect(find.text('선택 선수: 어떤이'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('종료 기록은 선택 선수를 따르며 돌아와도 선택이 유지된다', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.widgetWithText(ChoiceChip, '누군가 · 미드필더'));
    await tester.pumpAndSettle();
    final preview = find.text('경기 종료 기록 미리보기');
    await tester.scrollUntilVisible(preview, 200);
    expect(tester.getSize(find.byType(FilledButton)).height, 53);
    await tester.tap(preview);
    await tester.pumpAndSettle();

    expect(find.text('누군가의 경기 기록'), findsOneWidget);
    expect(find.text('0골'), findsOneWidget);
    expect(find.text('2개'), findsOneWidget);
    expect(find.text('85분'), findsOneWidget);
    expect(find.text('가상 경기 종료 화면 미리보기입니다.'), findsOneWidget);

    await tester.tap(find.text('선수 선택으로 돌아가기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('선택 선수: 누군가'), -200);
    expect(find.text('선택 선수: 누군가'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 화면에서도 선수 변경과 종료 기록을 확인할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.widgetWithText(ChoiceChip, '어떤이 · 수비수'));
    await tester.pumpAndSettle();
    final preview = find.text('경기 종료 기록 미리보기');
    await tester.scrollUntilVisible(preview, 200);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('어떤이의 경기 기록'), findsOneWidget);
    expect(find.text('90분'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
