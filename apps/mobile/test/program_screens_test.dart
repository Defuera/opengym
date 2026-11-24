import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/about_me_screen.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/screens/program_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/screens/start_flow.dart';
import 'package:opengym/stores/context_store.dart';

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
  // ADR-030: the program is data for the coach. The start sheet has no program row; a session of a program comes from the
  // coach's proposal, which carries the program link.
  const StartProposal fromProgram = StartProposal(
    kind: 'gym',
    type: 'Gym',
    focus: 'Legs',
    reason: 'Session B of week 2',
    plan: Plan(id: 'x', focus: 'Legs', createdAt: 1, source: 'ai', rationale: 'Session B as written', exercises: <PlanExercise>[
      PlanExercise(name: 'Step-up', sets: <PlanSet>[PlanSet(reps: 10, kg: 0)]),
    ]),
    program: ProgramLink(programId: 'prog-1', week: 2, slot: 1, key: 'B'),
  );

  group('program and the start sheet', () {
    testWidgets('a running program adds no row to the start sheet', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      fake.programs.set(<Program>[kneeProgram()]);
      await t.pump();
      await openStart(t);
      expect(find.text('Knee for skiing'), findsNothing);
      expect(find.byWidgetPredicate((Widget w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('program-')), findsNothing);
    });

    test('a start proposal reads its program link, and a broken one is dropped', () {
      final StartProposal p = StartProposal.fromJson(<String, dynamic>{
        'kind': 'gym',
        'type': 'Gym',
        'program': <String, dynamic>{'programId': 'prog-1', 'week': 2, 'slot': 1, 'key': 'B'},
      });
      expect(p.program!.programId, 'prog-1');
      expect(p.program!.week, 2);
      expect(p.program!.slot, 1);
      expect(p.program!.key, 'B');
      expect(StartProposal.fromJson(<String, dynamic>{'kind': 'gym', 'type': 'Gym', 'program': <String, dynamic>{'programId': 'prog-1'}}).program, isNull);
      expect(StartProposal.fromJson(<String, dynamic>{'kind': 'gym', 'type': 'Gym'}).program, isNull);
    });

    testWidgets('a session from a program proposal carries the link and is sent with it', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await openHome(t);
      openProposal(t.state<NavigatorState>(find.byType(Navigator).first), d, fromProgram);
      await t.pumpAndSettle();
      expect(find.byType(SessionScreen), findsOneWidget);
      final Session a = d.store.active!;
      expect(a.program!.programId, 'prog-1');
      expect(a.program!.key, 'B');
      // The link is kept with the open session on the phone.
      expect(Session.fromJson(a.toJson()).program!.slot, 1);
      d.store.completeSet();
      final String id = d.store.finish()!;
      final Map<String, dynamic> wire = encodeSession(d.store.sessionById(id)!);
      expect(wire['programId'], 'prog-1');
      expect(wire['programWeek'], 2);
      expect(wire['programSlot'], 1);
      expect(wire['programKey'], 'B');
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
      expect(find.text('Chat about this program ›'), findsOneWidget);
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

    testWidgets('Chat about this program opens the chat about it', (WidgetTester t) async {
      final (FakeConvexClient _, AppDeps d) = await _deps(programs: <Program>[kneeProgram()]);
      d.coach.start();
      await _openScreen(t, ProgramScreen(deps: d, programId: 'prog-1'));
      expect(find.text('Chat about this program ›'), findsOneWidget);
      await t.tap(_key('program-change'));
      await t.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(d.coach.currentAbout?.id, 'prog-1');
      expect(find.text('Ask, or say what should change'), findsOneWidget);
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

    testWidgets('New program opens the chat about a new program; a program row opens its screen', (WidgetTester t) async {
      final AppDeps d = await open(t, <Program>[kneeProgram()]);
      d.coach.start();
      await t.scrollUntilVisible(_key('program-new'), 200);
      await t.tap(find.byKey(const ValueKey<String>('program-item-prog-1')));
      await t.pumpAndSettle();
      expect(find.byType(ProgramScreen), findsOneWidget);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(_key('program-new'), 200);
      await t.tap(_key('program-new'));
      await t.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(d.coach.currentAbout, isNotNull);
      expect(d.coach.currentAbout!.id, isNull);
      expect(find.text('Paste a program, or say what you want'), findsOneWidget);
    });

    testWidgets('without deps there is no Programs section', (WidgetTester t) async {
      final ContextStore notes = await sampleNotes();
      await launch(t, AboutMeScreen(about: storeOn(InMemoryAboutRepository(initial: sampleAbout())), notes: notes));
      expect(find.text('PROGRAMS'), findsNothing);
    });
  });
}
