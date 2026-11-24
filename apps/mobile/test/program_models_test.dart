import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/program_text.dart';
import 'package:opengym/widgets/program_view.dart';

import 'support/program_fixtures.dart';

Map<String, dynamic> _programJson() => <String, dynamic>{
      'programId': 'p1',
      'title': 'Knee',
      'purpose': 'Ski',
      'status': 'paused',
      'startsOn': '2026-11-16',
      'endsOn': '2026-12-13',
      'week': <String>['A', 'B'],
      'phases': <Map<String, dynamic>>[
        <String, dynamic>{
          'title': 'One',
          'weekFrom': 1,
          'weekTo': 4,
          'note': '',
          'sessions': <Map<String, dynamic>>[
            <String, dynamic>{
              'key': 'A',
              'title': 'Session A',
              'activity': 'Gym',
              'exercises': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'Squat',
                  'sets': <Map<String, dynamic>>[
                    <String, dynamic>{'reps': 8.0, 'kg': 40.0, 'max': false},
                  ],
                },
                <String, dynamic>{'name': 'Broken', 'sets': 'x', 'measure': 7},
              ],
            },
          ],
        },
      ],
      'rules': <String>['No leg extension'],
      'tests': <Map<String, dynamic>>[
        <String, dynamic>{'testId': 't1', 'text': 'Squat 10', 'doneOn': '2026-11-20'},
        <String, dynamic>{'testId': 't2', 'text': 'Bike 30'},
      ],
      'rev': 3.0,
      'now': <String, dynamic>{
        'state': 'running',
        'week': 2.0,
        'weeks': 4.0,
        'phaseIndex': 0.0,
        'slots': <Map<String, dynamic>>[
          <String, dynamic>{'slot': 0.0, 'key': 'A', 'title': 'Session A', 'done': true},
          <String, dynamic>{'slot': 1.0, 'key': 'B', 'title': 'Session B', 'done': false},
        ],
        'next': <String, dynamic>{
          'slot': 1.0,
          'key': 'B',
          'title': 'Session B',
          'activity': 'Gym',
          'exercises': <Map<String, dynamic>>[],
        },
      },
    };

void main() {
  test('Program.fromJson reads a full program, with the slots and the next session', () {
    final Program p = decodeProgram(_programJson());
    expect(p.programId, 'p1');
    expect(p.status, 'paused');
    expect(p.active, isFalse);
    expect(p.rev, 3);
    expect(p.phases.single.sessions.single.exercises.map((PlanExercise e) => e.name), contains('Squat'));
    expect(p.tests.map((ProgramTest t) => t.done), <bool>[true, false]);
    expect(p.tests.first.testId, 't1');
    final ProgramNow n = p.now!;
    expect(n.running, isTrue);
    expect(n.week, 2);
    expect(n.slotsDone, 1);
    expect(n.next!.key, 'B');
    expect(n.nextPosition, 2);
  });

  test('Program.fromJson is tolerant: odd input gives defaults, never throws', () {
    final Program p = Program.fromJson(<String, dynamic>{'status': 'weird', 'phases': 5, 'tests': <Object?>['a text', 3]});
    expect(p.status, 'active');
    expect(p.phases, isEmpty);
    expect(p.now, isNull);
    expect(p.tests.first.text, 'a text');
    expect(Program.fromJson(<String, dynamic>{}).title, '');
  });

  test('Proposal.fromJson reads the frame and the program value', () {
    final Proposal p = decodeProposal(<String, dynamic>{
      'proposalId': 'x',
      'target': <String, dynamic>{'kind': 'program', 'id': 'prog-9'},
      'status': 'ready',
      'approval': 'explicit',
      'origin': 'feedback',
      'reason': 'Because',
      'value': <String, dynamic>{'title': 'T', 'startsOn': '2026-11-16', 'endsOn': '2026-11-22', 'tests': <String>['one']},
    })!;
    expect(p.ready, isTrue);
    expect(p.explicit, isTrue);
    expect(p.targetId, 'prog-9');
    expect(p.program!.title, 'T');
    expect(p.program!.tests.single.text, 'one');
    expect(decodeProposal(null), isNull);
    final Proposal f = Proposal.fromJson(<String, dynamic>{'proposalId': 'y', 'status': 'failed', 'approval': 'none', 'error': 'No'});
    expect(f.program, isNull);
    expect(f.explicit, isFalse);
    expect(f.error, 'No');
  });

  test('decodeAccepted reads the program id and refuses an answer without one', () {
    expect(decodeAccepted(<String, dynamic>{'programId': 'p7'}), 'p7');
    expect(() => decodeAccepted(null), throwsA(anything));
  });

  test('a session keeps its program link in local storage and in the API shape', () {
    final Session s = Session(
      id: 's1',
      kind: 'gym',
      type: 'Gym',
      startedAt: 1,
      endedAt: 2,
      program: const ProgramLink(programId: 'p1', week: 2, slot: 1, key: 'B'),
    );
    final Session back = Session.fromJson(s.toJson());
    expect(back.program!.programId, 'p1');
    expect(back.program!.week, 2);
    expect(back.program!.slot, 1);
    expect(back.program!.key, 'B');
    final Map<String, dynamic> wire = encodeSession(s);
    expect(wire['programId'], 'p1');
    expect(wire['programWeek'], 2);
    expect(wire['programSlot'], 1);
    expect(wire['programKey'], 'B');
  });

  test('an old stored session has no program and loads fine; the API shape has no program keys', () {
    final Session old = Session.fromJson(<String, dynamic>{'id': 'o', 'kind': 'gym', 'type': 'Gym', 'startedAt': 1, 'endedAt': 2});
    expect(old.program, isNull);
    expect(encodeSession(old).keys.where((String k) => k.startsWith('program')), isEmpty);
    expect(Session.fromJson(<String, dynamic>{'id': 'o', 'kind': 'gym', 'type': 'Gym', 'startedAt': 1, 'programId': 'p'}).program, isNull);
  });

  test('words: dates, weeks, status line, start line and exercise lines', () {
    expect(dayText('2026-12-19'), '19 Dec');
    expect(dayText('nonsense'), 'nonsense');
    expect(weeksText(1, 1), 'Week 1');
    expect(weeksText(2, 3), 'Weeks 2 to 3');
    final Program p = kneeProgram();
    expect(programDates(p), '16 Nov to 13 Dec · 4 weeks');
    expect(programStatusLine(p), 'Week 2 of 4 · 1 of 5 sessions');
    expect(programStatusLine(kneeProgram(status: 'paused')), 'Paused · Week 2 of 4 · 1 of 5 sessions');
    expect(programStatusLine(kneeProgram(state: 'before')), 'Starts 16 Nov');
    expect(programStatusLine(kneeProgram(state: 'ended')), 'Ended');
    expect(programShortLine(p), 'Week 2 of 4');
    expect(programShortLine(kneeProgram(status: 'done')), 'Done');
    expect(planLine(const PlanExercise(name: 'Leg press', sets: <PlanSet>[PlanSet(reps: 12, kg: 40), PlanSet(reps: 12, kg: 40), PlanSet(reps: 12, kg: 40)])), 'Leg press · 3 × 12 × 40 kg');
    expect(planLine(const PlanExercise(name: 'Step-up', sets: <PlanSet>[PlanSet(reps: 10, kg: 0)])), 'Step-up · 1 × 10');
    expect(planLine(const PlanExercise(name: 'Row', sets: <PlanSet>[PlanSet(reps: 8, kg: 20), PlanSet(reps: 6, kg: 25)])), 'Row · 8 × 20 kg, 6 × 25 kg');
    expect(planLine(const PlanExercise(name: 'Wall sit', measure: 'time', sets: <PlanSet>[PlanSet(reps: 0, kg: 0, minutes: 0.5)])), 'Wall sit · 30 s');
  });

  test('programView marks the current phase and takes this week\'s slots only for a running active program', () {
    final ProgramView live = programView(kneeProgram());
    expect(live.phases.map((ProgramPhaseView x) => x.current), <bool>[false, true, false, false]);
    expect(live.slots!.map((ProgramSlotView s) => s.done), <bool>[true, false, false, false, false]);
    expect(live.tests.first.done, isTrue);
    final ProgramView paused = programView(kneeProgram(status: 'paused'));
    expect(paused.slots, isNull);
    final ProgramView proposal = programView(kneeValue());
    expect(proposal.slots, isNull);
    expect(proposal.week, <String>['Session A', 'Session B', 'Session A', 'Bike', 'Bike']);
    expect(proposal.phases.map((ProgramPhaseView x) => x.open), <bool>[true, false, false, false]);
  });
}
