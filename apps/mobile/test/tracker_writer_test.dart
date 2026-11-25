import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/data/tracker_prefs.dart';
import 'package:opengym/data/tracker_source.dart';
import 'package:opengym/data/tracker_write_mapping.dart';
import 'package:opengym/data/tracker_writer.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';

import 'support/plans.dart';

int _ms(int h, [int m = 0]) => DateTime(2026, 11, 25, h, m).millisecondsSinceEpoch;

Session _gym({String id = 's1', String type = 'Gym', String? focus = 'Upper', int? end}) => Session(
      id: id,
      kind: 'gym',
      type: type,
      focus: focus,
      startedAt: _ms(18),
      endedAt: end ?? _ms(19, 5),
      exercises: <Exercise>[
        Exercise(id: 'e1', name: 'Bench press', sets: <SetEntry>[SetEntry(reps: 8, kg: 60, done: true)]),
      ],
    );

Session _timed(String type, {double? km, double? setKm}) => Session(
      id: 't1',
      kind: 'gym',
      type: type,
      startedAt: _ms(7),
      endedAt: _ms(7, 40),
      distanceKm: km,
      exercises: <Exercise>[
        Exercise(id: 'e2', name: type, measure: measureTime, sets: <SetEntry>[SetEntry.time(40, distanceKm: setKm, done: true)]),
      ],
    );

({TrackerWriter writer, FakeTrackerSource source, TrackerSettings settings, InMemoryTrackerPrefs prefs}) _make({bool on = true}) {
  final FakeTrackerSource source = FakeTrackerSource();
  final InMemoryTrackerPrefs prefs = InMemoryTrackerPrefs(TrackerPrefsState(writeOn: on));
  final TrackerSettings settings = TrackerSettings(prefs);
  return (writer: TrackerWriter(source: source, settings: settings), source: source, settings: settings, prefs: prefs);
}

void main() {
  group('mapping', () {
    test('gym and sessions with sets are strength training; the title is activity and focus', () {
      final WorkoutWrite w = workoutWriteFor(_gym())!;
      expect(w.kind, WorkoutKind.strength);
      expect(w.title, 'Gym Upper');
      expect(w.start, DateTime(2026, 11, 25, 18));
      expect(w.end, DateTime(2026, 11, 25, 19, 5));
      expect(w.distanceKm, isNull);
      expect(workoutWriteFor(_gym(type: 'Home', focus: null))!.kind, WorkoutKind.strength);
      expect(workoutWriteFor(_gym(type: 'Home', focus: null))!.title, 'Home');
    });

    test('activities are mapped by name; an unknown one is other', () {
      expect(workoutKindFor(_timed('Run')), WorkoutKind.running);
      expect(workoutKindFor(_timed('Morning walk')), WorkoutKind.walking);
      expect(workoutKindFor(_timed('Cycling')), WorkoutKind.cycling);
      expect(workoutKindFor(_timed('Bike ride')), WorkoutKind.cycling);
      expect(workoutKindFor(_timed('Swim')), WorkoutKind.swimming);
      expect(workoutKindFor(_timed('Hiking')), WorkoutKind.hiking);
      expect(workoutKindFor(_timed('Rowing')), WorkoutKind.rowing);
      expect(workoutKindFor(_timed('Yoga')), WorkoutKind.yoga);
      expect(workoutKindFor(_timed('Padel')), WorkoutKind.other);
    });

    test('distance: the session own, else the sum of the time sets, else none', () {
      expect(workoutWriteFor(_timed('Run', km: 6.2))!.distanceKm, 6.2);
      expect(workoutWriteFor(_timed('Run', setKm: 5))!.distanceKm, 5);
      expect(workoutWriteFor(_timed('Run'))!.distanceKm, isNull);
    });

    test('nothing sound to write: no end, an end not after the start, or over 12 hours', () {
      final Session open = _gym()..endedAt = null;
      expect(workoutWriteFor(open), isNull);
      expect(workoutWriteFor(_gym(end: _ms(18))), isNull);
      expect(workoutWriteFor(_gym(end: DateTime(2026, 11, 26, 8).millisecondsSinceEpoch)), isNull);
    });
  });

  group('writer', () {
    test('off by default: nothing is written', () async {
      final m = _make(on: false);
      await m.settings.load();
      expect(await m.writer.onSessionFinished(_gym()), WriteOutcome.off);
      expect(m.source.written, isEmpty);
    });

    test('on: writes the finished session once, remembers its id, and a second finish writes nothing', () async {
      final m = _make();
      await m.settings.load();
      expect(await m.writer.onSessionFinished(_gym()), WriteOutcome.written);
      expect(m.source.written, hasLength(1));
      expect(m.source.written.single.title, 'Gym Upper');
      expect(m.prefs.state.writtenIds, <String>{'s1'});
      expect(await m.writer.onSessionFinished(_gym()), WriteOutcome.alreadyWritten);
      expect(await m.writer.onSessionFinished(_gym(id: 's2')), WriteOutcome.written);
      expect(m.source.written, hasLength(2));
    });

    test('a failed write never throws, is not remembered, and may be tried again', () async {
      final m = _make();
      await m.settings.load();
      m.source.writeError = StateError('plugin');
      expect(await m.writer.onSessionFinished(_gym()), WriteOutcome.failed);
      m.source.writeError = null;
      m.source.writeResult = false;
      expect(await m.writer.onSessionFinished(_gym()), WriteOutcome.refused);
      expect(m.prefs.state.writtenIds, isEmpty);
      m.source.writeResult = true;
      expect(await m.writer.onSessionFinished(_gym()), WriteOutcome.written);
    });

    test('a session with nothing sound to write is skipped', () async {
      final m = _make();
      await m.settings.load();
      expect(await m.writer.onSessionFinished(_gym(end: _ms(18))), WriteOutcome.nothingToWrite);
      expect(m.source.written, isEmpty);
    });

    test('the switch asks for write permission; it stays off when that fails or there is no store', () async {
      final m = _make(on: false);
      await m.settings.load();
      m.source.connectWriteResult = false;
      expect(await m.writer.setOn(true), isFalse);
      expect(m.writer.on, isFalse);
      m.source.connectWriteResult = true;
      m.source.isAvailable = false;
      expect(await m.writer.setOn(true), isFalse);
      m.source.isAvailable = true;
      expect(await m.writer.setOn(true), isTrue);
      expect(m.writer.on, isTrue);
      expect(m.prefs.state.writeOn, isTrue);
      expect(m.source.connectWriteCalls, 2);
      expect(await m.writer.setOn(false), isFalse);
      expect(m.writer.on, isFalse);
    });

    test('finishing a session in the app writes one workout, and a failing store does not stop the finish', () async {
      final AppStore store = AppStore(InMemorySessionRepository());
      await store.load();
      final m = _make();
      await m.settings.load();
      // As compose wires it.
      store.onSessionSaved = (String id) => unawaited(m.writer.onSessionFinished(store.sessionById(id)!));

      store.begin(focus: 'Push', prepared: pushPlan());
      store.completeSet();
      final String? first = store.finish();
      await Future<void>.delayed(Duration.zero);
      expect(first, isNotNull);
      expect(m.source.written, hasLength(1));
      expect(m.source.written.single.kind, WorkoutKind.strength);
      expect(m.prefs.state.writtenIds, <String>{first!});

      m.source.writeError = StateError('store is gone');
      store.begin(focus: 'Pull', prepared: pushPlan());
      store.completeSet();
      final String? second = store.finish();
      await Future<void>.delayed(Duration.zero);
      expect(second, isNotNull);
      expect(store.sessions.map((Session s) => s.id), contains(second));
    });
  });
}
