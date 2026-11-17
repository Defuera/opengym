import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/models.dart';

Map<String, dynamic> _roundTrip(Map<String, dynamic> j) {
  return jsonDecode(jsonEncode(j)) as Map<String, dynamic>;
}

void main() {
  test('Plan round-trips', () {
    final Map<String, dynamic> json = <String, dynamic>{
      'id': 'p1',
      'type': 'Gym',
      'focus': 'Push',
      'createdAt': 1000,
      'source': 'ai',
      'rationale': 'Sample rationale.',
      'exercises': <Object>[
        <String, dynamic>{
          'name': 'Bench press',
          'note': 'Sample note',
          'sets': <Object>[
            <String, dynamic>{'reps': 5, 'kg': 40.0, 'max': false},
            <String, dynamic>{'reps': 1, 'kg': 50.0, 'max': true},
          ],
        },
      ],
    };
    final Plan p = Plan.fromJson(json);
    expect(p.exercises.first.note, 'Sample note');
    expect(p.exercises.first.sets.last.max, isTrue);
    expect(_roundTrip(p.toJson()), json);
  });

  test('Goal round-trips and keeps optional fields optional', () {
    final Map<String, dynamic> json = <String, dynamic>{
      'id': 'g1',
      'title': 'Sample goal',
      'kind': 'strength',
      'status': 'active',
      'source': 'user',
      'createdAt': 5,
      'exercise': 'Squat',
      'targetKg': 100.0,
      'sessionsPerWeek': 3,
    };
    final Goal g = Goal.fromJson(json);
    expect(g.done, isFalse);
    expect(_roundTrip(g.toJson()), json);

    final Goal bare = Goal.fromJson(<String, dynamic>{
      'id': 'g2',
      'title': 'Bare',
      'kind': 'custom',
      'status': 'done',
      'source': 'ai',
      'createdAt': 6,
    });
    expect(bare.done, isTrue);
    expect(bare.toJson().containsKey('targetKg'), isFalse);
  });

  test('DashboardModule round-trips for each known type', () {
    final List<Map<String, dynamic>> modules = <Map<String, dynamic>>[
      <String, dynamic>{'type': 'stat', 'label': 'Sessions', 'value': '3', 'highlighted': true},
      <String, dynamic>{
        'type': 'goal_progress',
        'goalId': 'g1',
        'title': 'Sample',
        'current': '50 kg',
        'target': '80 kg',
        'fraction': 0.5,
      },
      <String, dynamic>{
        'type': 'trend',
        'title': 'Sample',
        'unit': 'kg',
        'points': <Object>[
          <String, dynamic>{'t': 1, 'value': 2.0},
          <String, dynamic>{'t': 2, 'value': 3.0},
        ],
      },
      <String, dynamic>{
        'type': 'consistency',
        'title': 'Sample',
        'days': <bool>[true, false, true],
      },
      <String, dynamic>{
        'type': 'recent_sessions',
        'items': <Object>[
          <String, dynamic>{'title': 'A', 'subtitle': 'B', 'trailing': 'C'},
        ],
      },
      <String, dynamic>{'type': 'note', 'text': 'Sample'},
    ];
    for (final Map<String, dynamic> j in modules) {
      final DashboardModule m = DashboardModule.fromJson(j);
      expect(m.known, isTrue, reason: '${j['type']}');
      expect(_roundTrip(m.toJson()), j, reason: '${j['type']}');
    }
  });

  test('goal_progress allows a null fraction', () {
    final DashboardModule m = DashboardModule.fromJson(<String, dynamic>{
      'type': 'goal_progress',
      'goalId': 'g',
      'title': 'T',
      'current': '1',
      'target': '2',
      'fraction': null,
    });
    expect(m.fraction, isNull);
    expect(m.toJson()['fraction'], isNull);
  });

  test('Dashboard ignores unknown module types', () {
    final Dashboard d = Dashboard.fromJson(<String, dynamic>{
      'days': 30,
      'source': 'rules',
      'modules': <Object>[
        <String, dynamic>{'type': 'hologram', 'x': 1},
        <String, dynamic>{'type': 'note', 'text': 'Kept'},
      ],
    });
    expect(d.days, 30);
    expect(d.modules.length, 1);
    expect(d.modules.first.text, 'Kept');
  });

  test('gym Session serialises to the contract shape', () {
    final Session s = Session(
      id: 's1',
      kind: 'gym',
      type: 'Gym',
      focus: 'Push',
      startedAt: 1000,
      endedAt: 5000,
      exercises: <Exercise>[
        Exercise(
          id: 'local-id',
          name: 'Bench press',
          note: 'local only',
          sets: <SetEntry>[SetEntry(reps: 5, kg: 40, done: true, at: 2000)],
        ),
      ],
    );
    final Map<String, dynamic> j = s.toContractJson();
    expect(j['source'], 'app');
    expect(j['endedAt'], 5000);
    expect(j.containsKey('planNote'), isFalse);
    final Map<String, dynamic> ex =
        (j['exercises'] as List<Object?>).first as Map<String, dynamic>;
    expect(ex.keys.toSet(), <String>{'name', 'sets'});
    final Map<String, dynamic> st =
        (ex['sets'] as List<Object?>).first as Map<String, dynamic>;
    expect(st, <String, dynamic>{'reps': 5, 'kg': 40.0, 'max': false, 'at': 2000});

    final Session back = Session.fromJson(_roundTrip(j));
    expect(back.exercises.first.sets.first.done, isTrue);
    expect(back.exercises.first.sets.first.kg, 40);
    expect(back.source, 'app');
    expect(j['focus'], 'Push');
    expect(back.focus, 'Push');
    expect(j['type'], 'Gym');
  });

  test('a legacy gym session (type Upper, no focus) reads as Gym with a focus', () {
    final Map<String, dynamic> legacy = <String, dynamic>{
      'id': 'old',
      'kind': 'gym',
      'type': 'Upper',
      'startedAt': 1,
      'endedAt': 2,
      'exercises': <Object>[],
    };
    final Session s = Session.fromJson(legacy);
    expect(s.type, 'Gym');
    expect(s.focus, 'Upper');
    expect(Session.fromJson(_roundTrip(s.toJson())).focus, 'Upper');
    final Session run = Session.fromJson(<String, dynamic>{
      'id': 'r', 'kind': 'activity', 'type': 'Run', 'focus': 'Easy', 'startedAt': 1, 'endedAt': 2,
    });
    expect(run.type, 'Run');
    expect(run.focus, 'Easy');
    expect(run.toContractJson()['focus'], 'Easy');
    expect(Session.fromJson(<String, dynamic>{'id': 'x', 'kind': 'activity', 'type': 'Run', 'startedAt': 1, 'endedAt': 2}).toContractJson().containsKey('focus'), isFalse);
  });

  test('Prediction and Plan read the legacy shape', () {
    final Prediction p = Prediction.fromJson(<String, dynamic>{'kind': 'gym', 'type': 'Legs', 'reason': 'r'});
    expect(p.type, 'Gym');
    expect(p.focus, 'Legs');
    expect(Prediction.fromJson(p.toJson()).focus, 'Legs');
    expect(Plan.fromJson(<String, dynamic>{'id': 'p', 'type': 'Upper', 'createdAt': 1}).focus, 'Upper');
  });

  test('activity Session carries minutes, distance, note and no exercises', () {
    final Session s = Session(
      id: 'a1',
      kind: 'activity',
      type: 'Cycle',
      startedAt: 1000,
      endedAt: 61000,
      minutes: 1,
      distanceKm: 0.5,
      note: 'Sample',
      source: 'import',
      importId: 'imp1',
    );
    final Map<String, dynamic> j = s.toContractJson();
    expect(j['exercises'], isEmpty);
    expect(j['minutes'], 1);
    expect(j['distanceKm'], 0.5);
    expect(j['note'], 'Sample');
    expect(j['source'], 'import');
    expect(j['importId'], 'imp1');
    final Session back = Session.fromJson(_roundTrip(s.toJson()));
    expect(back.importId, 'imp1');
    expect(back.distanceKm, 0.5);
  });

  test('ImportJob and Review parse from contract JSON', () {
    final ImportJob j = ImportJob.fromJson(<String, dynamic>{
      'id': 'i1',
      'status': 'done',
      'total': 2,
      'processed': 2,
      'counts': <String, dynamic>{'sessions': 3, 'goals': 1, 'context': 0},
      'notes': <String>['n'],
      'createdAt': 9,
    });
    expect(j.finished, isTrue);
    expect(j.counts.sessions, 3);
    final Review r = Review.fromJson(<String, dynamic>{
      'sessionId': 's',
      'source': 'rules',
      'summary': 'Sample',
      'changes': <String>['a'],
    });
    expect(r.changes, <String>['a']);
  });
}
