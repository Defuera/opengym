import 'package:flutter_test/flutter_test.dart';
import 'support/plans.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/data/outbox.dart';
import 'package:opengym/data/session_sync.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';
import 'package:opengym/stores/goals_store.dart';

import 'support/fake_convex_client.dart';

Session _session(String id, {bool failed = false, int ended = 2000}) => Session(
      id: id,
      kind: 'gym',
      type: 'Gym',
      focus: 'Push',
      startedAt: 1000,
      endedAt: ended,
      exercises: <Exercise>[
        Exercise(id: 'e1', name: 'Bench press', sets: <SetEntry>[
          SetEntry(reps: 6, kg: 70, failed: failed, done: true, at: 1500),
        ]),
      ],
    );

Outbox _outbox(
  FakeConvexClient fake,
  InMemoryOutboxRepository repo, {
  bool Function()? connected,
}) =>
    Outbox(
      repo: repo,
      client: fake,
      isConnected: connected ?? () => fake.online,
      retryAfter: const Duration(hours: 1),
    );

Future<AppStore> _store() async {
  final AppStore s = AppStore(InMemorySessionRepository());
  await s.load();
  return s;
}

void main() {
  test('writes wait on disk offline, survive a restart, replay in order', () async {
    final FakeConvexClient fake = FakeConvexClient()..online = false;
    final InMemoryOutboxRepository repo = InMemoryOutboxRepository();
    final Outbox first = _outbox(fake, repo);
    await first.saveSession(_session('s1'));
    await first.createGoal(goalId: 'g1', title: 'Bench 100', kind: 'strength');
    await first.updateGoal('g1', const GoalPatch(status: 'done'));
    await first.removeSession('s0');
    expect(first.length, 4);
    expect(fake.calls, isEmpty);
    expect(repo.stored.length, 4); // on disk before anything is sent

    // "Restart": a new Outbox reads the same disk.
    fake.online = true;
    final Outbox second = _outbox(fake, repo);
    await second.load();
    expect(second.length, 4);
    await second.flush();
    expect(fake.calls, <String>[
      'saveSession:s1',
      'createGoal:g1',
      'updateGoal:g1',
      'removeSession:s0',
    ]);
    expect(second.isEmpty, isTrue);
    expect(repo.stored, isEmpty);
    expect(fake.serverGoals['g1']!.done, isTrue);
  });

  test('a newer save of the same session replaces the waiting one', () async {
    final FakeConvexClient fake = FakeConvexClient()..online = false;
    final Outbox o = _outbox(fake, InMemoryOutboxRepository());
    await o.saveSession(_session('s1'));
    await o.saveSession(_session('s1', ended: 3000));
    expect(o.length, 1);
    expect(o.ops.single.args['session']['endedAt'], 3000);
  });

  test('nothing is sent while not connected, and sending starts on reconnect', () async {
    final FakeConvexClient fake = FakeConvexClient();
    bool up = false;
    final Outbox o = _outbox(fake, InMemoryOutboxRepository(), connected: () => up);
    await o.saveSession(_session('s1'));
    expect(fake.calls, isEmpty);
    up = true;
    await o.flush();
    expect(fake.calls, <String>['saveSession:s1']);
  });

  test('a transient failure keeps the write and stops; order is kept', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final Outbox o = _outbox(fake, InMemoryOutboxRepository());
    fake.failNext = const ConvexCallException.unreachable();
    await o.saveSession(_session('s1'));
    await o.createGoal(goalId: 'g1', title: 'x', kind: 'custom');
    // s1 failed once, then g1 must not jump ahead of it.
    expect(fake.calls, <String>['saveSession:s1', 'createGoal:g1']);
    expect(o.isEmpty, isTrue);
  });

  test('a poison write is parked after 5 tries and the next write goes through', () async {
    final FakeConvexClient fake = FakeConvexClient()..poison.add('saveSession:bad');
    final Outbox o = _outbox(fake, InMemoryOutboxRepository());
    await o.saveSession(_session('bad')); // try 1
    await o.createGoal(goalId: 'g1', title: 'x', kind: 'custom'); // try 2, blocked
    expect(o.length, 2);
    await o.flush(); // 3
    await o.flush(); // 4
    expect(o.parkedCount, 0);
    await o.flush(); // 5: parked, then g1 goes through
    expect(o.parkedCount, 1);
    expect(o.parked.single.targetId, 'bad');
    expect(o.length, 0);
    expect(fake.calls, <String>['createGoal:g1']);
    expect(o.pendingSessionIds, <String>{'bad'});
  });

  test('failures are not counted while offline or with a wrong token', () async {
    final FakeConvexClient fake = FakeConvexClient()..poison.add('saveSession:bad');
    bool up = false;
    final Outbox o = _outbox(fake, InMemoryOutboxRepository(), connected: () => up);
    await o.saveSession(_session('bad'));
    for (int i = 0; i < 8; i++) {
      await o.flush();
    }
    expect(o.ops.single.failures, 0);
    // Link says up but the send fails because the link dropped: not verified.
    up = true;
    for (int i = 0; i < 4; i++) {
      fake.failNext = const ConvexCallException.unauthorized();
      await o.flush();
    }
    expect(o.ops.single.failures, 0);
    expect(o.parkedCount, 0);
  });

  test('parked writes survive a restart and retry moves them back', () async {
    final FakeConvexClient fake = FakeConvexClient()..poison.add('saveSession:bad');
    final InMemoryOutboxRepository repo = InMemoryOutboxRepository();
    final Outbox first = _outbox(fake, repo);
    await first.saveSession(_session('bad'));
    for (int i = 0; i < 5; i++) {
      await first.flush();
    }
    expect(first.parkedCount, 1);

    final Outbox second = _outbox(fake, repo);
    await second.load();
    expect(second.parkedCount, 1);
    expect(second.length, 0);
    await second.flush();
    expect(fake.calls, isEmpty); // parked writes are not sent on their own

    fake.poison.clear();
    await second.retryParked();
    expect(fake.calls, <String>['saveSession:bad']);
    expect(second.parkedCount, 0);
    expect(second.isEmpty, isTrue);
    expect(repo.stored, isEmpty);
  });

  test('a refused write is dropped and reported; a wrong token keeps it', () async {
    final FakeConvexClient fake = FakeConvexClient()..online = false;
    final Outbox o = _outbox(fake, InMemoryOutboxRepository());
    await o.updateGoal('missing', const GoalPatch(status: 'done'));
    await o.saveSession(_session('s1'));
    final List<Rejection> seen = <Rejection>[];
    o.rejections.listen(seen.add);
    fake.online = true;
    await o.flush();
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.message, 'goal not found');
    expect(fake.calls, <String>['updateGoal:missing', 'saveSession:s1']);

    fake.failNext = const ConvexCallException.unauthorized();
    await o.saveSession(_session('s2'));
    expect(o.length, 1);
    expect(o.lastError, contains('token'));
  });

  test('a live server update reaches the sessions in the store', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppStore store = await _store();
    final Outbox o = _outbox(fake, InMemoryOutboxRepository());
    final SessionSync sync = SessionSync(client: fake, store: store, outbox: o)..start();
    await pump();
    expect(store.sessions, isEmpty);
    fake.serverChanged(() => fake.serverSessions['imp1'] = _session('imp1'));
    await pump();
    expect(store.sessions.map((Session s) => s.id), <String>['imp1']);
    fake.serverChanged(() => fake.serverSessions['imp2'] = _session('imp2', ended: 3000));
    await pump();
    expect(store.sessions.map((Session s) => s.id), <String>['imp1', 'imp2']);
    await sync.stop();
  });

  test('a session with a write waiting is not overwritten by the server', () async {
    final FakeConvexClient fake = FakeConvexClient()..online = false;
    final AppStore store = await _store();
    final Outbox o = _outbox(fake, InMemoryOutboxRepository());
    final SessionSync sync = SessionSync(client: fake, store: store, outbox: o)..start();
    await pump();

    // Local copy, write waiting offline.
    final Session local = _session('s1', failed: true);
    store.sessions.add(local);
    await o.saveSession(local);
    // The server has an older version of the same session.
    fake.serverChanged(() => fake.serverSessions['s1'] = _session('s1', ended: 1500));
    await pump();
    expect(store.sessionById('s1')!.endedAt, 2000);
    expect(store.sessionById('s1')!.exercises.single.sets.single.failed, isTrue);

    // A removal waiting offline: the server still has it, it stays gone.
    store.removeSession('s1');
    await o.removeSession('s1');
    fake.serverChanged(() => fake.serverSessions['s1'] = _session('s1'));
    await pump();
    expect(store.sessionById('s1'), isNull);

    // Once the outbox is empty the server wins again.
    fake.online = true;
    await o.flush();
    expect(fake.serverSessions.containsKey('s1'), isFalse);
    await sync.stop();
  });

  test('goals: live updates show, and a waiting change is not undone', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final Outbox o = _outbox(fake, InMemoryOutboxRepository(), connected: () => false);
    final GoalsStore goals = GoalsStore(client: fake, outbox: o)..start();
    await pump();
    fake.serverChanged(() => fake.serverGoals['g1'] = const Goal(
        id: 'g1',
        title: 'Squat 120',
        kind: 'strength',
        status: 'active',
        source: 'user',
        createdAt: 1));
    await pump();
    expect(goals.goals.single.title, 'Squat 120');
    expect(goals.loading, isFalse);

    // Offline: mark done. The overlay shows it at once.
    await goals.markDone(goals.goals.single);
    expect(goals.goals.single.done, isTrue);
    // The server pushes its old copy: the waiting change still wins.
    fake.serverChanged(() => fake.serverGoals['g1'] = fake.serverGoals['g1']!);
    await pump();
    expect(goals.goals.single.done, isTrue);

    // A new goal made offline shows too, then the server confirms it.
    await goals.add(title: 'Run 5k', kind: 'custom');
    expect(goals.goals.length, 2);
    await goals.remove(goals.goals.first);
    expect(goals.goals.length, 1);
    goals.dispose();
  });

  test('the failed flag survives the model, the store, the outbox and the server', () async {
    // model JSON, local and contract
    final SetEntry a = SetEntry(reps: 6, kg: 70, failed: true, done: true);
    expect(SetEntry.fromJson(a.toJson()).failed, isTrue);
    expect(a.toContractJson()['failed'], isTrue);

    // store: mark on the current set, then finish
    final AppStore store = await _store();
    store.begin(focus: 'Push', prepared: pushPlan());
    store.toggleFailed();
    expect(store.currentSet!.failed, isTrue);
    store.completeSet();
    expect(store.active!.exercises.first.sets.first.failed, isTrue);
    store.toggleFailed(); // current is now the next set
    store.toggleFailed(); // off again
    expect(store.currentSet!.failed, isFalse);

    final FakeConvexClient fake = FakeConvexClient()..online = false;
    final InMemoryOutboxRepository repo = InMemoryOutboxRepository();
    final Outbox o = _outbox(fake, repo);
    store.onSessionSaved = (String id) => o.saveSession(store.sessionById(id)!);
    store.finish();
    final String id = store.sessions.single.id;
    await Future<void>.delayed(Duration.zero);

    // restart, send, read back through the codec
    fake.online = true;
    final Outbox restarted = _outbox(fake, repo);
    await restarted.load();
    await restarted.flush();
    final Session onServer = fake.serverSessions[id]!;
    expect(onServer.exercises.first.sets.first.failed, isTrue);
    final Session back = decodeSession(encodeSession(onServer));
    expect(back.exercises.first.sets.first.failed, isTrue);
    expect(back.exercises.first.sets.first.reps, 6);
  });

  test('mergeRemote replaces only changed content and never deletes', () async {
    final AppStore store = await _store();
    store.sessions.add(_session('s1'));
    expect(store.mergeRemote(<Session>[_session('s1')]), 0);
    expect(store.mergeRemote(<Session>[_session('s1', ended: 2500)]), 1);
    expect(store.sessionById('s1')!.endedAt, 2500);
    expect(store.mergeRemote(<Session>[]), 0);
    expect(store.sessions.length, 1);
  });
}
