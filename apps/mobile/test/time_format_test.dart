import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/store.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/set_editor_card.dart';
import 'package:opengym/widgets/time_format.dart';

void main() {
  group('formatTimeEntry', () {
    test('seconds under a minute, whole minutes, minutes and seconds', () {
      expect(formatTimeEntry(0.5), '30 s');
      expect(formatTimeEntry(0.0833), '5 s');
      expect(formatTimeEntry(10), '10 min');
      expect(formatTimeEntry(1), '1 min');
      expect(formatTimeEntry(1.5), '1:30 min');
      expect(formatTimeEntry(1.0833), '1:05 min');
      expect(formatTimeEntry(0.9833), '59 s');
    });

    test('editor value and unit', () {
      expect(timeValue(0.5), '30');
      expect(timeUnit(0.5), 'SEC');
      expect(timeValue(10), '10');
      expect(timeUnit(10), 'MIN');
      expect(timeValue(1.5), '1:30');
      expect(timeUnit(1.5), 'MIN');
    });
  });

  group('stepMinutes', () {
    double sec(double m) => timeSeconds(m).toDouble();

    test('5 s steps up to 2 minutes', () {
      expect(sec(stepMinutes(2, -1)), 115);
      expect(sec(stepMinutes(115 / 60, 1)), 120);
      expect(sec(stepMinutes(0.5, 1)), 35);
    });

    test('1 minute steps above 2 minutes', () {
      expect(sec(stepMinutes(2, 1)), 180);
      expect(sec(stepMinutes(3, -1)), 120);
      expect(sec(stepMinutes(20, 1)), 1260);
      expect(sec(stepMinutes(20, -5)), 900);
    });

    test('lowest value is 5 s, highest 600 minutes', () {
      expect(sec(stepMinutes(10 / 60, -1)), 5);
      expect(sec(stepMinutes(5 / 60, -1)), 5);
      expect(stepMinutes(600, 1), 600);
    });

    test('stores seconds / 60 rounded to 4 decimals', () {
      expect(stepMinutes(10 / 60, -1), 0.0833);
    });
  });

  group('time editor card', () {
    Future<AppStore> open(WidgetTester t, double minutes, {double? km}) async {
      final AppStore store = AppStore(InMemorySessionRepository());
      await store.load();
      store.begin(prepared: <Exercise>[
        Exercise(
          id: 'w',
          name: 'Wall sit',
          measure: measureTime,
          fresh: false,
          sets: <SetEntry>[SetEntry.time(minutes, distanceKm: km)],
        ),
      ]);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: OG.ground),
        home: SessionScreen(store: store),
      ));
      await t.pump();
      return store;
    }

    testWidgets('0.5 shows 30 with SEC; no Add distance for a short entry', (WidgetTester t) async {
      await open(t, 0.5);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('SEC'), findsOneWidget);
      expect(find.text('Add distance'), findsNothing);
    });

    testWidgets('10 min shows 10 with MIN and Add distance', (WidgetTester t) async {
      await open(t, 10);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('MIN'), findsOneWidget);
      expect(find.text('Add distance'), findsOneWidget);
    });

    testWidgets('a short entry with a distance keeps its field', (WidgetTester t) async {
      await open(t, 1, km: 0.4);
      expect(find.byKey(const ValueKey<String>('time-distance')), findsOneWidget);
    });

    testWidgets('plus and minus step 5 s and the row shows the new text', (WidgetTester t) async {
      final AppStore store = await open(t, 0.5);
      await t.tap(find.widgetWithIcon(StepperButton, Icons.add));
      await t.pump();
      expect(find.text('35'), findsOneWidget);
      expect(store.currentSet!.minutes, 0.5833);
    });
  });

  group('parseTimeEntry', () {
    test('minutes and seconds, seconds, plain minutes', () {
      expect(parseTimeEntry('2:30'), 2.5);
      expect(parseTimeEntry(' 0:45 '), 0.75);
      expect(parseTimeEntry('45s'), 0.75);
      expect(parseTimeEntry('90 sec'), 1.5);
      expect(parseTimeEntry('10'), 10);
      expect(parseTimeEntry('2,5'), 2.5);
      expect(parseTimeEntry('3 min'), 3);
    });

    test('not a time gives null; the limits hold', () {
      expect(parseTimeEntry(''), isNull);
      expect(parseTimeEntry('abc'), isNull);
      expect(parseTimeEntry('2:75'), isNull);
      expect(parseTimeEntry('1s'), 0.0833); // never under 5 s
      expect(parseTimeEntry('9999'), 600);
    });

    test('the text to edit is always m:ss', () {
      expect(timeEntryText(2), '2:00');
      expect(timeEntryText(2.5), '2:30');
      expect(timeEntryText(0.5), '0:30');
    });
  });
}
