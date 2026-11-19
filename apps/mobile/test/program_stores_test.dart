import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/stores/program_store.dart';
import 'package:opengym/stores/proposal_run.dart';

import 'support/fake_convex_client.dart';
import 'support/program_fixtures.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('ProgramStore', () {
    test('lists what the server sends; active leaves out paused and done; byId finds one', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProgramStore s = ProgramStore(client: fake)..start();
      await _settle();
      expect(s.programs, isEmpty);
      expect(s.loading, isFalse);
      fake.programs.set(<Program>[
        kneeProgram(),
        kneeProgram(id: 'p2', status: 'paused'),
        kneeProgram(id: 'p3', status: 'done'),
      ]);
      await _settle();
      expect(s.programs.length, 3);
      expect(s.active.map((Program p) => p.programId), <String>['prog-1']);
      expect(s.byId('p2')!.status, 'paused');
      expect(s.byId('nope'), isNull);
    });

    test('an error keeps the last list and shows nothing new', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProgramStore s = ProgramStore(client: fake)..start();
      fake.programs.set(<Program>[kneeProgram()]);
      await _settle();
      // A second store whose subscription fails: nothing new shows, no throw.
      fake.programsError = const ConvexCallException.unreachable();
      final ProgramStore failing = ProgramStore(client: fake)..start();
      await _settle();
      expect(failing.programs, isEmpty);
      expect(failing.loading, isFalse);
      expect(s.programs.length, 1);
    });

    test('setStatus and remove call the server', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProgramStore s = ProgramStore(client: fake);
      await s.setStatus('prog-1', 'paused');
      await s.remove('prog-1');
      expect(fake.calls, containsAll(<String>['setProgramStatus:prog-1:paused', 'removeProgram:prog-1']));
    });
  });

  group('ProposalRun', () {
    test('ask: building, then ready with the value; it waits with no time limit', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('prepare my knee for skiing');
      expect(run.phase, ProposalPhase.building);
      expect(fake.proposalsSent.single.text, 'prepare my knee for skiing');
      expect(fake.proposalsSent.single.targetId, isNull);
      fake.answerProposal(kneeProposal(status: 'building', id: fake.lastProposalId));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(run.phase, ProposalPhase.building);
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await _settle();
      expect(run.phase, ProposalPhase.ready);
      expect(run.proposal!.program!.title, 'Knee for skiing');
      run.dispose();
    });

    test('a change of a program sends the target id', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake, targetId: 'prog-1');
      await run.ask('no running');
      expect(fake.proposalsSent.single.targetId, 'prog-1');
      run.dispose();
    });

    test('rebuild: keeps the shown proposal while busy, points at it, then shows the new one', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('a knee program');
      final String first = fake.lastProposalId;
      fake.answerProposal(kneeProposal(id: first));
      await _settle();
      await run.rebuild('only two days a week');
      expect(run.phase, ProposalPhase.rebuilding);
      expect(run.proposal!.proposalId, first);
      final ProposalSent sent = fake.proposalsSent.last;
      expect(sent.feedback, 'only two days a week');
      expect(sent.previousProposalId, first);
      expect(sent.text, isNull);
      fake.answerProposal(kneeProposal(id: sent.proposalId));
      await _settle();
      expect(run.phase, ProposalPhase.ready);
      expect(run.proposal!.proposalId, sent.proposalId);
      run.dispose();
    });

    test('a failed proposal shows the server error and keeps the typed text', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('my text');
      fake.answerProposal(kneeProposal(status: 'failed', id: fake.lastProposalId, error: 'Could not make a program.'));
      await _settle();
      expect(run.phase, ProposalPhase.failed);
      expect(run.error, 'Could not make a program.');
      expect(run.text, 'my text');
      expect(run.proposal, isNull);
      run.dispose();
    });

    test('a failed rebuild ends in failed (the server declined the old proposal)', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('x');
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await _settle();
      await run.rebuild('change');
      fake.answerProposal(kneeProposal(status: 'failed', id: fake.lastProposalId));
      await _settle();
      expect(run.phase, ProposalPhase.failed);
      expect(run.error, isNotEmpty);
      run.dispose();
    });

    test('a send error fails the run with a short line; a refused request shows the server words', () async {
      final FakeConvexClient fake = FakeConvexClient()..online = false;
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('x');
      expect(run.phase, ProposalPhase.failed);
      expect(run.error, 'Could not reach the coach. Try again.');
      fake.online = true;
      fake.failNext = const ConvexCallException('Too long.', kind: ConvexFailure.rejected);
      await run.ask('x');
      expect(run.error, 'Too long.');
      run.dispose();
    });

    test('accept: returns the program id and the run is applied', () async {
      final FakeConvexClient fake = FakeConvexClient()..acceptedProgramId = 'prog-9';
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('x');
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await _settle();
      expect(await run.accept(), isTrue);
      expect(run.programId, 'prog-9');
      expect(run.phase, ProposalPhase.applied);
      expect(fake.calls, contains('acceptProposal:${fake.lastProposalId}'));
      run.dispose();
    });

    test('accept refused: the proposal stays, the error shows; a changed program ends the run', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('x');
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await _settle();
      fake.acceptError = const ConvexCallException('A limit rules out Leg extension.', kind: ConvexFailure.rejected);
      expect(await run.accept(), isFalse);
      expect(run.phase, ProposalPhase.ready);
      expect(run.error, 'A limit rules out Leg extension.');
      fake.acceptError = const ConvexCallException('The program changed. Ask again.', kind: ConvexFailure.rejected);
      expect(await run.accept(), isFalse);
      expect(run.phase, ProposalPhase.failed);
      expect(run.error, 'The program changed. Ask again.');
      run.dispose();
    });

    test('a stale status from the server ends the run', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('x');
      fake.answerProposal(kneeProposal(id: fake.lastProposalId));
      await _settle();
      fake.answerProposal(kneeProposal(status: 'stale', id: fake.lastProposalId));
      await _settle();
      expect(run.phase, ProposalPhase.failed);
      expect(run.error, 'The program changed. Ask again.');
      run.dispose();
    });

    test('cancel declines on the server and goes back to the start; a late answer changes nothing', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun run = ProposalRun(client: fake);
      await run.ask('x');
      final String id = fake.lastProposalId;
      await run.cancel();
      expect(run.phase, ProposalPhase.idle);
      expect(fake.calls, contains('declineProposal:$id'));
      fake.answerProposal(kneeProposal(id: id), id: id);
      await _settle();
      expect(run.phase, ProposalPhase.idle);
      expect(run.proposal, isNull);
      run.dispose();
    });

    test('resume takes over a waiting proposal: ready shows it, building waits', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final ProposalRun ready = ProposalRun(client: fake)..resume(kneeProposal(id: 'w1'));
      expect(ready.phase, ProposalPhase.ready);
      expect(ready.proposal!.proposalId, 'w1');
      final ProposalRun building = ProposalRun(client: fake)..resume(kneeProposal(status: 'building', id: 'w2'));
      expect(building.phase, ProposalPhase.building);
      fake.answerProposal(kneeProposal(id: 'w2'), id: 'w2');
      await _settle();
      expect(building.phase, ProposalPhase.ready);
      ready.dispose();
      building.dispose();
    });
  });
}
