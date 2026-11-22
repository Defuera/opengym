import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_types.dart';
import 'package:opengym/data/outbox_ops.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/screens/session_recap_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/widgets/body_figure.dart';
import 'package:opengym/widgets/og_button.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

final int _end = DateTime.now().millisecondsSinceEpoch - 86400000;

Session _gym({String source = 'app', String? importId}) => Session(
      id: 's1',
      kind: 'gym',
      type: 'Gym',
      focus: 'Upper',
      startedAt: _end - 52 * 60000,
      endedAt: _end,
      note: 'Felt strong',
      source: source,
      importId: importId,
      exercises: <Exercise>[
        Exercise(id: 'e1', name: 'Bench press', sets: <SetEntry>[
          SetEntry(reps: 8, kg: 60, done: true),
          SetEntry(reps: 6, kg: 70, failed: true, done: true),
        ]),
        Exercise(id: 'e2', name: 'Bike', measure: measureTime, sets: <SetEntry>[
          SetEntry.time(25, distanceKm: 10.9, done: true),
        ]),
      ],
    );

final Session _other = Session(
  id: 's0',
  kind: 'gym',
  type: 'Gym',
  startedAt: _end - 7 * 86400000,
  endedAt: _end - 7 * 86400000 + 3600000,
  exercises: <Exercise>[
    Exercise(id: 'x1', name: 'Squat', sets: <SetEntry>[SetEntry(reps: 5, kg: 100, done: true)]),
  ],
);

final Session _run = Session(
  id: 'a1',
  kind: 'activity',
  type: 'Run',
  focus: 'Easy',
  startedAt: _end - 30 * 60000,
  endedAt: _end,
  minutes: 30,
  distanceKm: 5.2,
  note: 'Cold morning',
);

/// A tall screen, so a whole form is on it.
void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 3200);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

Future<(FakeConvexClient, AppDeps)> _open(
  WidgetTester t,
  Session s, {
  bool openEdit = false,
}) async {
  _tall(t);
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps d = await testDeps(fake, connected: false, sessions: <Session>[_other, s]);
  // As in compose.dart: an edit goes to the outbox under the same id.
  d.store.onSessionRemoved = (String id) => d.outbox.removeSession(id);
  d.store.onSessionEdited = (String id) => d.outbox.saveSession(d.store.sessionById(id)!);
  await t.pumpWidget(MaterialApp(home: SessionRecapScreen(deps: d, sessionId: s.id)));
  await t.pump();
  if (openEdit) {
    await t.tap(find.byKey(const ValueKey<String>('recap-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('recap-edit')));
    await t.pumpAndSettle();
  }
  return (fake, d);
}

/// Lets the outbox finish its (real) async work.
Future<void> _outbox(WidgetTester t) =>
    t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  group('recap', () {
    testWidgets('lists every set, the note, the time and the duration', (WidgetTester t) async {
      await _open(t, _gym());
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Upper'), findsOneWidget);
      expect(find.text('8 × 60 kg'), findsOneWidget);
      expect(find.text('6½ × 70 kg'), findsOneWidget);
      expect(find.text('25 min, 10.9 km'), findsOneWidget);
      expect(find.text('Felt strong'), findsOneWidget);
      expect(t.widget<Text>(_key('recap-when')).data, contains('52 min'));
      expect(t.widget<Text>(_key('recap-when')).data, contains('Started'));
    });

    testWidgets('an import hides the duration and the start time', (WidgetTester t) async {
      await _open(t, _gym(source: 'import', importId: 'i1'));
      final String when = t.widget<Text>(_key('recap-when')).data!;
      expect(when, isNot(contains('min')));
      expect(when, isNot(contains('Started')));
      expect(find.text('8 × 60 kg'), findsOneWidget);
    });

    testWidgets('an activity session shows minutes, distance and note', (WidgetTester t) async {
      await _open(t, _run);
      expect(t.widget<Text>(_key('recap-activity')).data, '30 min, 5.2 km');
      expect(find.text('Cold morning'), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('recap-menu')), findsOneWidget);
    });

    testWidgets('shows the coach review and the body figure when they exist', (WidgetTester t) async {
      _tall(t);
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake, sessions: <Session>[_gym()]);
      fake.reviews['s1'] = Live<Stored<Review?>>()
        ..set(const Stored<Review?>(
          Review(sessionId: 's1', source: 'rules', summary: 'Bench went up.', changes: <String>['+2.5 kg']),
          stored: true,
        ));
      fake.loads['s1'] = Live<Map<String, int>?>()..set(<String, int>{'chest': 3, 'triceps': 1});
      await t.pumpWidget(MaterialApp(home: SessionRecapScreen(deps: d, sessionId: 's1')));
      await t.pump();
      expect(find.text('Coach review'), findsOneWidget);
      expect(find.text('Bench went up.'), findsOneWidget);
      expect(t.widget<BodyFigure>(_key('recap-figure')).load['chest'], 3);
    });

    testWidgets('Home opens the recap from the Recent list', (WidgetTester t) async {
      _tall(t);
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake, sessions: <Session>[_run]);
      await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
      await t.pump();
      await t.tap(find.text('Run'));
      await t.pumpAndSettle();
      expect(_key('recap-activity'), findsOneWidget);
    });

    testWidgets('Delete asks first, then removes the session', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _run);
      await t.tap(find.byKey(const ValueKey<String>('recap-menu')));
      await t.pumpAndSettle();
      await t.tap(_key('recap-delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete this session?'), findsOneWidget);
      expect(find.text('It is removed from your log now and erased for good after 72 hours.'), findsOneWidget);
      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      expect(d.store.sessionById('a1'), isNotNull);
      await t.tap(find.byKey(const ValueKey<String>('recap-menu')));
      await t.pumpAndSettle();
      await t.tap(_key('recap-delete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete session'));
      await t.pumpAndSettle();
      expect(d.store.sessionById('a1'), isNull);
      await _outbox(t);
      expect(d.outbox.ops.map((o) => o.type).toList(), contains(OutboxOp.sessionRemove));
    });
  });

  group('delete', () {
    testWidgets('confirm: the recap closes, Home no longer lists it, the server gets remove, no save is queued',
        (WidgetTester t) async {
      _tall(t);
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake, sessions: <Session>[_run]);
      d.store.onSessionRemoved = (String id) => d.outbox.removeSession(id);
      await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
      await t.pump();
      await t.tap(find.text('Run'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('recap-menu')));
      await t.pumpAndSettle();
      await t.tap(_key('recap-delete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete session'));
      await t.pumpAndSettle();
      await _outbox(t);
      expect(_key('recap-activity'), findsNothing);
      expect(find.byType(SessionRecapScreen), findsNothing);
      expect(find.text('Run'), findsNothing);
      expect(d.store.sessionById('a1'), isNull);
      expect(fake.calls, contains('removeSession:a1'));
      expect(d.outbox.ops.where((o) => o.type == OutboxOp.sessionSave), isEmpty);
    });

    testWidgets('closing the sheet without a choice keeps the session', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _open(t, _run);
      await t.tap(find.byKey(const ValueKey<String>('recap-menu')));
      await t.pumpAndSettle();
      await t.tap(_key('recap-delete'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
      await t.pumpAndSettle();
      expect(find.text('Delete this session?'), findsNothing);
      expect(d.store.sessionById('a1'), isNotNull);
      expect(fake.calls, isNot(contains('removeSession:a1')));
    });
  });

  group('edit', () {
    Map<String, dynamic> saved(AppDeps d) =>
        d.outbox.ops.singleWhere((o) => o.type == OutboxOp.sessionSave).args['session'] as Map<String, dynamic>;

    testWidgets('change a set, save: same id, source and kind kept', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) =
          await _open(t, _gym(source: 'import', importId: 'i1'), openEdit: true);
      expect(find.text('Save'), findsOneWidget);
      await t.tap(find.byIcon(Icons.add).first); // reps of the selected set: 8 -> 9
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      final Map<String, dynamic> j = saved(d);
      expect(j['id'], 's1');
      expect(j['kind'], 'gym');
      expect(j['source'], 'import');
      expect(j['importId'], 'i1');
      final List<dynamic> ex = j['exercises'] as List<dynamic>;
      expect(((ex.first as Map<String, dynamic>)['sets'] as List<dynamic>).first['reps'], 9);
      expect(d.store.sessionById('s1')!.exercises.first.sets.first.reps, 9);
      expect(d.store.active, isNull);
      expect(find.text('9 × 60 kg'), findsOneWidget); // back on the recap
    });

    testWidgets('add an exercise from the log, then save', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _gym(), openEdit: true);
      await t.ensureVisible(_key('edit-add-exercise'));
      await t.tap(_key('edit-add-exercise'));
      await t.pumpAndSettle();
      await t.tap(find.text('Squat'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      expect(d.store.sessionById('s1')!.exercises.map((Exercise e) => e.name), <String>['Bench press', 'Bike', 'Squat']);
      expect(saved(d)['id'], 's1');
    });

    testWidgets('a new name asks how it is tracked', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _gym(), openEdit: true);
      await t.ensureVisible(_key('edit-add-exercise'));
      await t.tap(_key('edit-add-exercise'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Rowing');
      await t.pump();
      await t.tap(find.text('Add "Rowing"'));
      await t.pumpAndSettle();
      expect(find.text('How do you track Rowing?'), findsOneWidget);
      await t.tap(find.widgetWithText(OgButton, 'Time'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      final Exercise e = d.store.sessionById('s1')!.exercises.last;
      expect((e.name, e.isTime), ('Rowing', true));
    });

    testWidgets('remove an exercise, save', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _gym(), openEdit: true);
      await t.tap(_key('edit-remove-e2'));
      await t.pumpAndSettle();
      expect(find.text('Remove this exercise?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      expect(d.store.sessionById('s1')!.exercises.map((Exercise e) => e.name), <String>['Bench press']);
    });

    testWidgets('Keep it keeps the exercise', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _gym(), openEdit: true);
      await t.tap(_key('edit-remove-e2'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      expect(d.store.sessionById('s1')!.exercises.length, 2);
    });

    testWidgets('add and remove a set', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _gym(), openEdit: true);
      await t.tap(find.text('Add set'));
      await t.pump();
      expect(find.text('Set 3'), findsOneWidget);
      // swipe the second row away (the third is the open editor)
      await t.drag(find.text('6½ × 70 kg', findRichText: true), const Offset(-600, 0));
      await t.pumpAndSettle();
      expect(find.text('Delete this set?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      expect(d.store.sessionById('s1')!.exercises.first.sets, hasLength(2));
      expect(d.store.sessionById('s1')!.exercises.first.sets.last.kg, 70);
    });

    testWidgets('note, focus and duration are saved; the end follows the start', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _gym(), openEdit: true);
      Future<void> type(String k, String v) async {
        await t.ensureVisible(_key(k));
        await t.enterText(find.descendant(of: _key(k), matching: find.byType(TextField)), v);
      }

      await type('edit-note', 'Better');
      await type('edit-focus', 'Push');
      await type('edit-minutes', '60');
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      final Session s = d.store.sessionById('s1')!;
      expect((s.note, s.focus), ('Better', 'Push'));
      expect(s.endedAt! - s.startedAt, 60 * 60000);
      expect(s.startedAt, _gym().startedAt);
      expect(s.source, 'app');
    });

    testWidgets('an activity session edits minutes, distance and note', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _run, openEdit: true);
      await t.enterText(find.descendant(of: _key('edit-minutes'), matching: find.byType(TextField)), '45');
      await t.enterText(find.descendant(of: _key('edit-km'), matching: find.byType(TextField)), '7,5');
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await _outbox(t);
      final Session s = d.store.sessionById('a1')!;
      expect((s.minutes, s.distanceKm, s.kind), (45, 7.5, 'activity'));
      expect(s.endedAt! - s.startedAt, 45 * 60000);
      expect(t.widget<Text>(_key('recap-activity')).data, '45 min, 7.5 km');
    });

    testWidgets('leaving with changes asks first; Save is off with none', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _open(t, _gym(), openEdit: true);
      await t.tap(find.byIcon(Icons.chevron_left)); // nothing changed: leaves at once
      await t.pumpAndSettle();
      expect(_key('recap-menu'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('recap-menu')));
      await t.pumpAndSettle();
      await t.tap(_key('recap-edit'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.add).first);
      await t.pump();
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      await t.tap(find.text('Leave without saving'));
      await t.pumpAndSettle();
      expect(_key('recap-menu'), findsOneWidget);
      expect(d.store.sessionById('s1')!.exercises.first.sets.first.reps, 8);
      expect(d.outbox.ops, isEmpty);
    });
  });

  testWidgets('finishing a session ends on its recap', (WidgetTester t) async {
    _tall(t);
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, connected: false);
    d.store.begin(prepared: <Exercise>[
      Exercise(id: 'e1', name: 'Bench press', sets: <SetEntry>[SetEntry(reps: 8, kg: 60, done: true)]),
    ]);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext c) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(c).push(
              MaterialPageRoute<void>(builder: (BuildContext c) => SessionScreen(store: d.store, deps: d)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Finish session'));
    await t.pumpAndSettle();
    expect(find.text('8 × 60 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('recap-menu')), findsOneWidget);
    expect(d.store.active, isNull);
  });

  test('updateSession keeps the open session and the order by time', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, sessions: <Session>[_other, _gym()]);
    d.store.begin(prepared: <Exercise>[]);
    final String open = d.store.active!.id;
    final Session moved = Session.fromJson(_gym().toJson())..startedAt = _end - 30 * 86400000..endedAt = _end - 30 * 86400000 + 60000;
    final List<String> told = <String>[];
    d.store.onSessionEdited = told.add;
    d.store.updateSession(moved);
    expect(d.store.sessions.map((Session s) => s.id), <String>['s1', 's0']);
    expect(d.store.active!.id, open);
    expect(told, <String>['s1']);
    d.store.updateSession(Session.fromJson(_run.toJson())..id = 'nope');
    expect(told, hasLength(1));
  });

  testWidgets('a session finished just now offers "Continue session"; a tap opens it again', (WidgetTester t) async {
    _tall(t);
    final AppDeps d = await testDeps(FakeConvexClient(), connected: false);
    d.store.begin(prepared: <Exercise>[
      Exercise(id: 'a', name: 'Leg Press', sets: <SetEntry>[SetEntry(reps: 12, kg: 30), SetEntry(reps: 12, kg: 30)]),
      Exercise(id: 'b', name: 'Wall Sit', measure: measureTime, sets: <SetEntry>[SetEntry.time(1)]),
    ]);
    d.store.completeSet();
    final String id = d.store.finish()!;
    await t.pumpWidget(MaterialApp(home: SessionRecapScreen(deps: d, sessionId: id)));
    await t.pump();
    expect(_key('recap-continue'), findsOneWidget);
    await t.tap(_key('recap-continue'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(find.byType(SessionRecapScreen), findsNothing);
    expect(d.store.active!.id, id);
    expect(d.store.active!.exercises.map((Exercise e) => e.name), <String>['Leg Press', 'Wall Sit']);
  });

  testWidgets('an older session has no "Continue session"', (WidgetTester t) async {
    await _open(t, _gym());
    expect(_key('recap-continue'), findsNothing);
  });
}
