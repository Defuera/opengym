import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/store.dart';
import 'package:opengym/theme.dart';

import 'support/load_fonts.dart';

Future<AppStore> _open(
  WidgetTester t, {
  String type = 'Home',
  String? focus,
  String? note,
  List<Exercise>? exercises,
}) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final AppStore store = AppStore(InMemorySessionRepository());
  await store.load();
  store.begin(
    prepared: exercises ??
        <Exercise>[
          Exercise(
              id: 'a',
              name: 'Curl',
              fresh: false,
              sets: <SetEntry>[SetEntry(reps: 8, kg: 10)]),
        ],
    activity: type,
    focus: focus,
    rationale: note,
  );
  await t.pumpWidget(MaterialApp(
    theme:
        ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
    home: SessionScreen(store: store),
  ));
  await t.pump();
  return store;
}

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);
  testWidgets('a long title shows in full on two lines',
      (WidgetTester t) async {
    await _open(t, type: 'Home accessories and warm-up mobility');
    final Finder title = find.text('Home accessories and warm-up mobility');
    expect(title, findsOneWidget);
    final RenderParagraph p = t.renderObject<RenderParagraph>(title);
    expect(p.didExceedMaxLines, isFalse);
    expect(t.getSize(title).height, lessThan(30 * 1.05 * 2 + 2));
  });

  testWidgets(
      'Why this session icon opens the full text in a sheet',
      (WidgetTester t) async {
    await _open(t);
    expect(find.byKey(const ValueKey<String>('why-icon')), findsOneWidget); // a session with an exercise
    final String long =
        ('Side delts and shins have had little direct work. ' * 6).trim();
    await _open(t, focus: 'Side delts, shins', note: long);
    expect(find.text(long), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('why-icon')));
    await t.pumpAndSettle();
    expect(find.text(long), findsOneWidget);
    expect(find.text('Side delts, shins'), findsNWidgets(2)); // under the title, and in the sheet
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(find.text(long), findsNothing);
  });

  testWidgets(
      'no feedback field in the main area, and no Change plan without a proposal',
      (WidgetTester t) async {
    await _open(t, focus: 'Legs', note: 'Legs are due');
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Rebuild'), findsNothing);
    expect(find.text('Change plan'), findsNothing);
    expect(find.text('End session'), findsNothing);
  });

  testWidgets('distance shows only when planned or after Add distance',
      (WidgetTester t) async {
    await _open(t, exercises: <Exercise>[
      Exercise(
          id: 'w',
          name: 'Warm-up',
          measure: measureTime,
          fresh: false,
          sets: <SetEntry>[SetEntry.time(10)]),
    ]);
    expect(find.byKey(const ValueKey<String>('time-distance')), findsNothing);
    expect(find.text('Add distance'), findsOneWidget);
    await t.tap(find.text('Add distance'));
    await t.pump();
    expect(find.byKey(const ValueKey<String>('time-distance')), findsOneWidget);
    expect(find.text('Add distance'), findsNothing);

    await _open(t, exercises: <Exercise>[
      Exercise(
          id: 'r',
          name: 'Run',
          measure: measureTime,
          fresh: false,
          sets: <SetEntry>[SetEntry.time(30, distanceKm: 5)]),
    ]);
    expect(find.byKey(const ValueKey<String>('time-distance')), findsOneWidget);
    expect(find.text('Add distance'), findsNothing);
  });

  testWidgets('the whole card scrolls together and the next button stays pinned',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 2, 420 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final AppStore store = AppStore(InMemorySessionRepository());
    await store.load();
    store.begin(prepared: <Exercise>[
      Exercise(
          id: 'a',
          name: 'Curl',
          fresh: false,
          note: 'n ' * 80,
          sets: <SetEntry>[
            for (int i = 0; i < 6; i++) SetEntry(reps: 8, kg: 10, done: true),
          ]),
    ]);
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(
            scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: SessionScreen(store: store)));
    await t.pump();
    final double before = t.getTopLeft(find.text('Curl').last).dy;
    expect(t.getRect(find.text('Finish session')).bottom, lessThanOrEqualTo(420));
    await t.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -150));
    await t.pump();
    expect(t.getTopLeft(find.text('Curl').last).dy,
        lessThan(before)); // the title moved with the card
    expect(t.getRect(find.text('Finish session')).bottom, lessThanOrEqualTo(420));
  });

  testWidgets('a swipe on the card shows the next and the previous exercise', (WidgetTester t) async {
    final AppStore store = await _open(t, exercises: <Exercise>[
      Exercise(id: 'a', name: 'Curl', fresh: false, sets: <SetEntry>[SetEntry(reps: 8, kg: 10)]),
      Exercise(id: 'b', name: 'Row', fresh: false, sets: <SetEntry>[SetEntry(reps: 8, kg: 30)]),
    ]);
    await t.pumpAndSettle();
    final Finder title = find.text('Curl').last;
    await t.fling(title, const Offset(-200, 0), 1000);
    await t.pumpAndSettle();
    expect(store.curEx, 1);
    await t.fling(find.text('Row').last, const Offset(-200, 0), 1000);
    await t.pumpAndSettle();
    expect(store.curEx, 1); // no exercise after the last one
    await t.fling(find.text('Row').last, const Offset(200, 0), 1000);
    await t.pumpAndSettle();
    expect(store.curEx, 0);
  });

  testWidgets('the add button stays in view with many exercises', (WidgetTester t) async {
    await _open(t, exercises: <Exercise>[
      for (int i = 0; i < 8; i++)
        Exercise(id: 'e$i', name: 'Exercise $i', fresh: false, sets: <SetEntry>[SetEntry(reps: 8, kg: 10)]),
    ]);
    await t.pumpAndSettle();
    final Rect r = t.getRect(find.byKey(const ValueKey<String>('add-exercise')));
    expect(r.right, lessThanOrEqualTo(390));
    expect(r.left, greaterThan(300));
  });
}
