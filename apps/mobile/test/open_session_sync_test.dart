import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/data/open_session_sync.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';

import 'support/fake_convex_client.dart';

/// ADR-028: the open session is the same on the phone and on the server.
Exercise _ex(String name, {bool done = false}) =>
    Exercise(id: 'id-$name', name: name, sets: <SetEntry>[SetEntry(reps: 12, kg: 30, done: done)]);

Session _remote(String id, List<Exercise> list) =>
    Session(id: id, kind: 'gym', type: 'Gym', focus: 'Legs', startedAt: 1, exercises: list);

Future<(AppStore, FakeConvexClient, OpenSessionSync, InMemorySessionRepository)> _open({bool online = true}) async {
  final InMemorySessionRepository repo = InMemorySessionRepository();
  final AppStore store = AppStore(repo);
  await store.load();
  final FakeConvexClient fake = FakeConvexClient()..online = online;
  final OpenSessionSync sync =
      OpenSessionSync(client: fake, store: store, isConnected: () => fake.online, delay: Duration.zero);
  sync.start();
  addTearDown(sync.stop);
  await pumpEventQueue(); // the subscription opens
  return (store, fake, sync, repo);
}

void main() {
  test('a started session goes to the server, and each change after it', () async {
    final (AppStore store, FakeConvexClient fake, OpenSessionSync sync, _) = await _open();
    store.begin(prepared: <Exercise>[_ex('Leg Press')]);
    expect(store.activeDirty, isTrue);
    await sync.flush();
    expect(fake.openPuts.single['id'], store.active!.id);
    expect(store.activeDirty, isFalse);
    expect(store.activeRev, 1);
    store.completeSet();
    await sync.flush();
    expect(fake.openPuts.length, 2);
    expect(((fake.openPuts.last['exercises'] as List<dynamic>).first as Map<String, dynamic>)['sets'][0]['done'], isTrue);
    expect(store.activeRev, 2);
  });

  test('a change made outside the phone appears in the open session', () async {
    final (AppStore store, FakeConvexClient fake, OpenSessionSync sync, _) = await _open();
    store.begin(prepared: <Exercise>[_ex('Treadmill Walk')]);
    await sync.flush();
    final String id = store.active!.id;
    int told = 0;
    store.addListener(() => told++);
    fake.openRemote.set(OpenRemote(session: _remote(id, <Exercise>[_ex('Squat'), _ex('Leg Press')]), rev: 2));
    await pumpEventQueue();
    expect(store.active!.id, id);
    expect(store.active!.exercises.map((Exercise e) => e.name), <String>['Squat', 'Leg Press']);
    expect(store.activeRev, 2);
    expect(store.activeDirty, isFalse);
    expect(told, 1);
    await sync.flush();
    expect(fake.openPuts.length, 1); // taking it is not a change to send back
  });

  test('the phone wins while it holds a change that is not sent', () async {
    final (AppStore store, FakeConvexClient fake, OpenSessionSync sync, _) = await _open();
    store.begin(prepared: <Exercise>[_ex('Leg Press')]);
    await sync.flush();
    final String id = store.active!.id;
    fake.online = false;
    store.completeSet(); // offline: stays on the phone
    await sync.flush();
    expect(store.activeDirty, isTrue);
    fake.openRemote.set(OpenRemote(session: _remote(id, <Exercise>[_ex('Squat')]), rev: 2));
    await pumpEventQueue();
    expect(store.active!.exercises.single.name, 'Leg Press');
    fake.online = true;
    await sync.flush();
    expect(fake.openPuts.last['exercises'][0]['name'], 'Leg Press');
    expect(store.activeDirty, isFalse);
    expect(store.active!.exercises.single.sets.single.done, isTrue);
  });

  test('an older or equal revision is not taken', () async {
    final (AppStore store, FakeConvexClient fake, OpenSessionSync sync, _) = await _open();
    store.begin(prepared: <Exercise>[_ex('Leg Press')]);
    await sync.flush();
    store.activeRev = 5;
    fake.openRemote.set(OpenRemote(session: _remote(store.active!.id, <Exercise>[_ex('Squat')]), rev: 5));
    await pumpEventQueue();
    expect(store.active!.exercises.single.name, 'Leg Press');
  });

  test('a finished session is cleared on the server and never opened again', () async {
    final (AppStore store, FakeConvexClient fake, OpenSessionSync sync, _) = await _open();
    store.begin(prepared: <Exercise>[_ex('Leg Press')]);
    await sync.flush();
    final String id = store.active!.id;
    store.completeSet();
    fake.online = false;
    store.finish();
    expect(store.pendingClear, id);
    // The server still shows it as open: the phone does not take it back.
    fake.openRemote.set(OpenRemote(session: _remote(id, <Exercise>[_ex('Leg Press')]), rev: 9));
    await pumpEventQueue();
    expect(store.active, isNull);
    fake.online = true;
    await sync.flush();
    expect(fake.openClears, <String>[id]);
    expect(store.pendingClear, isNull);
    expect(fake.openRemote.value!.session, isNull);
  });

  test('a session opened elsewhere is taken when the phone has none', () async {
    final (AppStore store, FakeConvexClient fake, _, _) = await _open();
    fake.openRemote.set(OpenRemote(session: _remote('far', <Exercise>[_ex('Bike', done: true), _ex('Squat')]), rev: 3));
    await pumpEventQueue();
    expect(store.active!.id, 'far');
    expect(store.hasDoneSet, isTrue);
    expect(store.activeRev, 3);
  });

  test('the marks survive a restart: an unsent change goes out after it', () async {
    final (AppStore store, FakeConvexClient fake, OpenSessionSync sync, InMemorySessionRepository repo) =
        await _open(online: false);
    store.begin(prepared: <Exercise>[_ex('Leg Press')]);
    await sync.flush();
    expect(fake.openPuts, isEmpty);
    await sync.stop();
    final AppStore again = AppStore(repo);
    await again.load();
    expect(again.activeDirty, isTrue);
    fake.online = true;
    final OpenSessionSync s2 = OpenSessionSync(client: fake, store: again, isConnected: () => true, delay: Duration.zero);
    s2.start();
    addTearDown(s2.stop);
    await pumpEventQueue();
    await s2.flush();
    expect(fake.openPuts.single['id'], again.active!.id);
  });

  test('the server lost the row: the phone sends its session again', () async {
    final (AppStore store, FakeConvexClient fake, OpenSessionSync sync, _) = await _open();
    store.begin(prepared: <Exercise>[_ex('Leg Press')]);
    await sync.flush();
    fake.openRemote.set(const OpenRemote());
    await pumpEventQueue();
    await sync.flush();
    expect(fake.openPuts.length, 2);
    expect(fake.openRemote.value!.session!.id, store.active!.id);
  });
}
