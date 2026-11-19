import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/about_me_screen.dart';
import 'package:opengym/screens/program_new_screen.dart';
import 'package:opengym/screens/program_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/stores/context_store.dart';
import 'package:opengym/widgets/og_button.dart';
import 'package:opengym/widgets/session_meta_row.dart';

import 'support/about_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/program_fixtures.dart';
import 'support/sheet_fixtures.dart';
import 'support/test_deps.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<(FakeConvexClient, AppDeps)> _deps({List<Program>? programs}) async {
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps d = await testDeps(fake);
  if (programs != null) {
    fake.programs.set(programs);
  }
  return (fake, d);
}

Future<void> _openScreen(WidgetTester t, Widget screen) => launch(t, screen);

void main() {
  group('start sheet row', () {
    testWidgets('a running active program is one compact row with its next session', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram()]);
      await t.pump();
      await openStart(t);
      expect(_key('program-row-prog-1'), findsOneWidget);
      expect(find.text('Knee for skiing'), findsOneWidget);
      expect(find.text('week 2 of 4 · next: Session B (2 of 5)'), findsOneWidget);
      expect(_key('program-open-prog-1'), findsOneWidget);
    });

    testWidgets('no row for a paused program, one that has not started, one that ended, or none', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      fake.programs.set(<Program>[
        kneeProgram(id: 'a', status: 'paused'),
        kneeProgram(id: 'b', state: 'before'),
        kneeProgram(id: 'c', state: 'ended'),
      ]);
      await t.pump();
      await openStart(t);
      expect(find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('program-row-')), findsNothing);
    });

    testWidgets('a tap starts the next session with the link; the written exercises and the reason show', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram()]);
      await t.pump();
      await openStart(t);
      await t.tap(_key('program-row-prog-1'));
      await t.pumpAndSettle();
      expect(find.byType(SessionScreen), findsOneWidget);
      final Session a = d.store.active!;
      expect(a.type, 'Gym');
      expect(a.focus, 'Session B');
      expect(a.planNote, 'Knee for skiing · week 2 · Session B');
      expect(a.exercises.map((Exercise e) => e.name), <String>['Step-up', 'Calf raise']);
      expect(a.exercises.first.sets.length, 3);
      expect(a.program!.programId, 'prog-1');
      expect(a.program!.week, 2);
      expect(a.program!.slot, 1);
      expect(a.program!.key, 'B');
      // The link is kept with the open session on the phone.
      expect(Session.fromJson(a.toJson()).program!.slot, 1);
    });

    testWidgets('a bike day opens as the activity of its session', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram(done: const <bool>[true, true, true, false, false])]);
      await t.pump();
      await openStart(t);
      await t.tap(_key('program-row-prog-1'));
      await t.pumpAndSettle();
      expect(d.store.active!.type, 'Cycling');
      expect(d.store.active!.program!.key, 'Bike');
      expect(d.store.active!.exercises.single.isTime, isTrue);
    });

    testWidgets('an open session with a done set is resumed, not replaced', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      d.store.begin(activity: 'Gym', prepared: <Exercise>[Exercise(id: 'x', name: 'Own', sets: <SetEntry>[SetEntry(reps: 5, kg: 5)])]);
      d.store.completeSet();
      fake.programs.set(<Program>[kneeProgram()]);
      await t.pump();
      await openStart(t);
      await t.tap(_key('program-row-prog-1'));
      await t.pumpAndSettle();
      expect(d.store.active!.exercises.single.name, 'Own');
      expect(d.store.active!.program, isNull);
    });

    testWidgets('the small button opens the Program screen', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram()]);
      await t.pump();
      await openStart(t);
      await t.tap(_key('program-open-prog-1'));
      await t.pumpAndSettle();
      expect(find.byType(ProgramScreen), findsOneWidget);
      expect(d.store.active, isNull);
    });

    testWidgets('with the week done the row says so and a tap opens the Program screen', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram(done: const <bool>[true, true, true, true, true])]);
      await t.pump();
      await openStart(t);
      expect(find.text('week 2 of 4 · week done'), findsOneWidget);
      await t.tap(_key('program-row-prog-1'));
      await t.pumpAndSettle();
      expect(find.byType(ProgramScreen), findsOneWidget);
    });

    testWidgets('feedback on a program session goes with the plan as it is; the link survives the replace', (WidgetTester t) async {
      t.view.physicalSize = const Size(800, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram()]);
      await t.pump();
      await openStart(t);
      await t.tap(_key('program-row-prog-1'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(MetaItem, 'Change plan'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'no step-ups, my knee hurts');
      await t.pump();
      await t.tap(find.widgetWithText(OgButton, 'Rebuild'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(fake.startNames.last, 'Gym');
      expect(fake.startFeedback.last, ('no step-ups, my knee hurts', null));
      expect(fake.startPreviousPlans.last!.map((Map<String, dynamic> e) => e['name']), <Object?>['Step-up', 'Calf raise']);
      fake.answerStart(StartRequest(
        requestId: fake.lastStartId,
        status: 'ready',
        proposal: const StartProposal(
          kind: 'gym',
          type: 'Gym',
          plan: Plan(id: 'x', focus: '', createdAt: 1, source: 'ai', rationale: 'Easier', exercises: <PlanExercise>[
            PlanExercise(name: 'Glute bridge', sets: <PlanSet>[PlanSet(reps: 12, kg: 0)]),
          ]),
        ),
      ));
      await t.pumpAndSettle();
      expect(d.store.active!.exercises.single.name, 'Glute bridge');
      expect(d.store.active!.program!.programId, 'prog-1');
      expect(d.store.active!.program!.key, 'B');
    });

    testWidgets('a finished program session is sent with its program, week and slot', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram()]);
      await t.pump();
      await openStart(t);
      await t.tap(_key('program-row-prog-1'));
      await t.pumpAndSettle();
      d.store.completeSet();
      final String id = d.store.finish()!;
      final Map<String, dynamic> wire = encodeSession(d.store.sessionById(id)!);
      expect(wire['programId'], 'prog-1');
      expect(wire['programWeek'], 2);
      expect(wire['programSlot'], 1);
      expect(wire['programKey'], 'B');
    });
  });

  group('new program screen', () {
    testWidgets('type, Propose, wait, read, Agree: the Program screen opens', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps(programs: <Program>[kneeProgram()]);
      await _openScreen(t, ProgramNewScreen(deps: d));
      expect(find.text('New program'), findsOneWidget);
      expect(t.widget<OgButton>(_key('program-propose')).onPressed, isNull);
      await t.enterText(find.byType(TextField), 'prepare my knee for skiing by 19 Dec');
      await t.pump();
      await t.tap(_key('program-propose'));
      await t.pump();
      expect(find.text('The coach is writing the program'), findsOneWidget);
      expect(fake.proposalsSent.single.text, 'prepare my knee for skiing by 19 Dec');
      expect(fake.proposalsSent.single.kind, 'program');
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await t.pump();
      await t.pump();
      expect(find.text('Four weeks, three kinds of day, built around the knee.'), findsOneWidget);
      expect(find.text('Knee for skiing'), findsOneWidget);
      await t.tap(_key('proposal-agree'));
      await t.pumpAndSettle();
      expect(fake.calls, contains('acceptProposal:${fake.lastProposalId}'));
      expect(find.byType(ProgramScreen), findsOneWidget);
      expect(find.byType(ProgramNewScreen), findsNothing);
      expect(find.text('Week 2 of 4 · 1 of 5 sessions'), findsOneWidget);
    });

    testWidgets('a failed proposal shows the error and keeps the text; Propose works again', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps();
      await _openScreen(t, ProgramNewScreen(deps: d));
      await t.enterText(find.byType(TextField), 'my wish');
      await t.pump();
      await t.tap(_key('program-propose'));
      await t.pump();
      fake.answerProposal(kneeProposal(status: 'failed', id: fake.lastProposalId, error: 'Could not make a program from that.'));
      await t.pump();
      await t.pump();
      expect(find.text('Could not make a program from that.'), findsOneWidget);
      expect(find.text('my wish'), findsOneWidget);
      await t.tap(_key('program-propose'));
      await t.pump();
      expect(fake.proposalsSent.length, 2);
    });

    testWidgets('feedback rebuilds: the proposal stays while busy, then the new one shows', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps();
      await _openScreen(t, ProgramNewScreen(deps: d));
      await t.enterText(find.byType(TextField), 'my wish');
      await t.pump();
      await t.tap(_key('program-propose'));
      await t.pump();
      final String first = fake.lastProposalId;
      fake.answerProposal(kneeProposal(id: first));
      await t.pump();
      await t.pump();
      await t.tap(find.text('Change something ›'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'only two days a week');
      await t.pump();
      await t.tap(find.widgetWithText(OgButton, 'Rebuild'));
      await t.pump();
      expect(fake.proposalsSent.last.feedback, 'only two days a week');
      expect(fake.proposalsSent.last.previousProposalId, first);
      expect(find.text('The coach is rebuilding the program…'), findsOneWidget);
      expect(find.text('Knee for skiing'), findsOneWidget);
      expect(t.widget<OgButton>(_key('proposal-agree')).onPressed, isNull);
    });

    testWidgets('Cancel on a proposal drops it and leaves the screen', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps();
      await _openScreen(t, ProgramNewScreen(deps: d));
      await t.enterText(find.byType(TextField), 'my wish');
      await t.pump();
      await t.tap(_key('program-propose'));
      await t.pump();
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await t.pump();
      await t.pump();
      await t.tap(_key('proposal-cancel'));
      await t.pumpAndSettle();
      expect(fake.calls, contains('declineProposal:${fake.lastProposalId}'));
      expect(find.byType(ProgramNewScreen), findsNothing);
    });

    testWidgets('Cancel while the coach writes stops waiting and keeps the typed text', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps();
      await _openScreen(t, ProgramNewScreen(deps: d));
      await t.enterText(find.byType(TextField), 'my wish');
      await t.pump();
      await t.tap(_key('program-propose'));
      await t.pump();
      await t.tap(find.widgetWithText(OgButton, 'Cancel'));
      await t.pump();
      expect(fake.calls, contains('declineProposal:${fake.lastProposalId}'));
      expect(find.text('my wish'), findsOneWidget);
      expect(find.text('The coach is writing the program'), findsNothing);
    });

    testWidgets('a proposal that waits on the server opens at once', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      fake.openProposals.set(<Proposal>[kneeProposal(id: 'waiting')]);
      final AppDeps d = await testDeps(fake);
      await _openScreen(t, ProgramNewScreen(deps: d));
      await t.pump();
      expect(find.text('Knee for skiing'), findsOneWidget);
      expect(_key('proposal-agree'), findsOneWidget);
      expect(_key('program-propose'), findsNothing);
    });

    testWidgets('a change of a program: its own question, and the target is sent', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps(programs: <Program>[kneeProgram()]);
      fake.openProposals.set(<Proposal>[kneeProposal(id: 'other-target')]); // a proposal for a NEW program: not shown here
      await _openScreen(t, ProgramNewScreen(deps: d, change: kneeProgram()));
      await t.pump();
      expect(find.text('Change program'), findsOneWidget);
      expect(find.text('What should change?'), findsOneWidget);
      expect(_key('proposal-agree'), findsNothing);
      await t.enterText(find.byType(TextField), 'no bike');
      await t.pump();
      await t.tap(_key('program-propose'));
      await t.pump();
      expect(fake.proposalsSent.single.targetId, 'prog-1');
    });

    testWidgets('a refused Agree keeps the proposal and shows the reason', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps();
      fake.acceptError = const ConvexCallException('A limit rules out Leg extension.', kind: ConvexFailure.rejected);
      await _openScreen(t, ProgramNewScreen(deps: d));
      await t.enterText(find.byType(TextField), 'wish');
      await t.pump();
      await t.tap(_key('program-propose'));
      await t.pump();
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await t.pump();
      await t.pump();
      await t.tap(_key('proposal-agree'));
      await t.pumpAndSettle();
      expect(find.text('A limit rules out Leg extension.'), findsOneWidget);
      expect(find.byType(ProgramNewScreen), findsOneWidget);
    });
  });

  group('program screen', () {
    testWidgets('shows the status line, the current phase and the slots', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _deps(programs: <Program>[kneeProgram()]);
      await _openScreen(t, ProgramScreen(deps: d, programId: 'prog-1'));
      expect(find.text('Week 2 of 4 · 1 of 5 sessions'), findsOneWidget);
      expect(find.text('Knee for skiing'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(_key('slot-0'), findsOneWidget);
      expect(find.text('Ask the coach to change it ›'), findsOneWidget);
    });

    testWidgets('the header line for a program that has not started and one that ended', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps(programs: <Program>[kneeProgram(state: 'before')]);
      await _openScreen(t, ProgramScreen(deps: d, programId: 'prog-1'));
      expect(find.text('Starts 16 Nov'), findsOneWidget);
      fake.programs.set(<Program>[kneeProgram(state: 'ended')]);
      await t.pump();
      expect(find.text('Ended'), findsOneWidget);
    });

    testWidgets('the menu pauses, then offers Resume; End sets done', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps(programs: <Program>[kneeProgram()]);
      await _openScreen(t, ProgramScreen(deps: d, programId: 'prog-1'));
      await t.tap(_key('program-menu'));
      await t.pumpAndSettle();
      await t.tap(_key('program-pause'));
      await t.pumpAndSettle();
      expect(fake.calls, contains('setProgramStatus:prog-1:paused'));
      fake.programs.set(<Program>[kneeProgram(status: 'paused')]);
      await t.pump();
      expect(find.text('Paused · Week 2 of 4 · 1 of 5 sessions'), findsOneWidget);
      await t.tap(_key('program-menu'));
      await t.pumpAndSettle();
      expect(_key('program-resume'), findsOneWidget);
      expect(_key('program-pause'), findsNothing);
      await t.tap(_key('program-end'));
      await t.pumpAndSettle();
      expect(fake.calls, contains('setProgramStatus:prog-1:done'));
    });

    testWidgets('delete asks first: Keep it deletes nothing; Delete removes it and leaves the screen', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _deps(programs: <Program>[kneeProgram()]);
      await _openScreen(t, ProgramScreen(deps: d, programId: 'prog-1'));
      await t.tap(_key('program-menu'));
      await t.pumpAndSettle();
      await t.tap(_key('program-delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete this program?'), findsOneWidget);
      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      expect(fake.calls.where((String c) => c.startsWith('removeProgram')), isEmpty);
      await t.tap(_key('program-menu'));
      await t.pumpAndSettle();
      await t.tap(_key('program-delete'));
      await t.pumpAndSettle();
      await t.tap(_key('confirm-delete'));
      await t.pumpAndSettle();
      expect(fake.calls, contains('removeProgram:prog-1'));
      expect(find.byType(ProgramScreen), findsNothing);
    });

    testWidgets('Ask the coach to change it opens the proposal flow for this program', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _deps(programs: <Program>[kneeProgram()]);
      await _openScreen(t, ProgramScreen(deps: d, programId: 'prog-1'));
      await t.tap(_key('program-change'));
      await t.pumpAndSettle();
      expect(find.byType(ProgramNewScreen), findsOneWidget);
      expect(find.text('What should change?'), findsOneWidget);
    });

    testWidgets('a program that is not on the list says so', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _deps(programs: <Program>[]);
      await _openScreen(t, ProgramScreen(deps: d, programId: 'gone'));
      expect(find.text('This program is not here any more.'), findsOneWidget);
    });
  });

  group('About me', () {
    Future<AppDeps> open(WidgetTester t, List<Program> programs) async {
      final (FakeConvexClient _, AppDeps d) = await _deps(programs: programs);
      final ContextStore notes = await sampleNotes();
      await launch(t, AboutMeScreen(about: storeOn(InMemoryAboutRepository(initial: sampleAbout())), notes: notes, deps: d));
      return d;
    }

    testWidgets('lists the programs of any status and a New program row', (WidgetTester t) async {
      await open(t, <Program>[kneeProgram(), kneeProgram(id: 'p2', status: 'paused')]);
      await t.scrollUntilVisible(find.text('PROGRAMS'), 200);
      expect(find.text('PROGRAMS'), findsOneWidget);
      expect(find.text('Week 2 of 4'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(_key('program-new'), findsOneWidget);
    });

    testWidgets('New program opens the proposal screen; a program row opens its screen', (WidgetTester t) async {
      await open(t, <Program>[kneeProgram()]);
      await t.scrollUntilVisible(_key('program-new'), 200);
      await t.tap(find.byKey(const ValueKey<String>('program-item-prog-1')));
      await t.pumpAndSettle();
      expect(find.byType(ProgramScreen), findsOneWidget);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(_key('program-new'), 200);
      await t.tap(_key('program-new'));
      await t.pumpAndSettle();
      expect(find.byType(ProgramNewScreen), findsOneWidget);
    });

    testWidgets('without deps there is no Programs section', (WidgetTester t) async {
      final ContextStore notes = await sampleNotes();
      await launch(t, AboutMeScreen(about: storeOn(InMemoryAboutRepository(initial: sampleAbout())), notes: notes));
      expect(find.text('PROGRAMS'), findsNothing);
    });
  });
}
