import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/api/fake_open_gym_api.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/data/sync_service.dart';
import 'package:opengym/data/sync_state_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';

Future<AppStore> _store() async {
  final AppStore store = AppStore(InMemorySessionRepository());
  await store.load();
  return store;
}

AppStore _finishOne(AppStore store) {
  store.begin('Push');
  store.completeSet();
  store.finish();
  return store;
}

void main() {
  test('outbox keeps a session while offline and pushes it when online', () async {
    final FakeOpenGymApi api = FakeOpenGymApi()..online = false;
    final AppStore store = _finishOne(await _store());
    final InMemorySyncStateRepository state = InMemorySyncStateRepository();
    final SyncService sync = SyncService(api: api, state: state, store: store);
    final String id = store.sessions.first.id;

    final bool pushedOffline = await sync.enqueue(id);
    expect(pushedOffline, isFalse);
    expect(sync.outbox, <String>[id]);
    expect(api.serverSessions, isEmpty);
    // Persisted, so a restart still knows what is waiting.
    expect((await state.load()).outbox, <String>[id]);

    api.online = true;
    final SyncResult r = await sync.sync();
    expect(r.ok, isTrue);
    expect(r.pushed, 1);
    expect(sync.outbox, isEmpty);
    expect(api.serverSessions.containsKey(id), isTrue);
    expect(api.serverSessions[id]!.source, 'app');
    expect((await state.load()).outbox, isEmpty);
  });

  test('a new SyncService resumes the persisted outbox', () async {
    final FakeOpenGymApi api = FakeOpenGymApi()..online = false;
    final AppStore store = _finishOne(await _store());
    final InMemorySyncStateRepository state = InMemorySyncStateRepository();
    final String id = store.sessions.first.id;
    await SyncService(api: api, state: state, store: store).enqueue(id);

    api.online = true;
    final SyncService restarted = SyncService(api: api, state: state, store: store);
    final SyncResult r = await restarted.sync();
    expect(r.pushed, 1);
    expect(api.putIds, <String>[id]);
  });

  test('sync never throws and reports the problem when offline', () async {
    final FakeOpenGymApi api = FakeOpenGymApi()..online = false;
    final AppStore store = _finishOne(await _store());
    final SyncService sync = SyncService(
      api: api,
      state: InMemorySyncStateRepository(),
      store: store,
    );
    await sync.enqueue(store.sessions.first.id);
    final SyncResult r = await sync.sync(full: true);
    expect(r.ok, isFalse);
    expect(r.error, isNotNull);
    expect(sync.outbox.length, 1);
  });

  test('pull merges imported sessions by id and never duplicates', () async {
    final FakeOpenGymApi api = FakeOpenGymApi();
    final AppStore store = _finishOne(await _store());
    final SyncService sync = SyncService(
      api: api,
      state: InMemorySyncStateRepository(),
      store: store,
    );
    final int now = DateTime.now().millisecondsSinceEpoch;
    api.serverSessions['imp-1'] = Session(
      id: 'imp-1',
      kind: 'activity',
      type: 'Cycle',
      startedAt: now - 7200000,
      endedAt: now - 3600000,
      minutes: 30,
      source: 'import',
      importId: 'job1',
    );

    final SyncResult first = await sync.sync(full: true);
    expect(first.pulled, 1);
    expect(store.sessions.length, 2);
    expect(store.sessionById('imp-1')!.source, 'import');
    // The phone's own session was pushed and came back: still only one copy.
    final SyncResult second = await sync.sync(full: true);
    expect(second.pulled, 0);
    expect(store.sessions.length, 2);

    // Undoing the import removes its sessions locally.
    sync.forgetImport('job1');
    expect(store.sessions.length, 1);
  });
}
