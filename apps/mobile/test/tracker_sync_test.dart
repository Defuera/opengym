import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_types.dart';
import 'package:opengym/data/tracker_payload.dart';
import 'package:opengym/data/tracker_prefs.dart';
import 'package:opengym/data/tracker_source.dart';
import 'package:opengym/data/tracker_sync.dart';

import 'support/fake_convex_client.dart';

DateTime _clock = DateTime(2026, 11, 25, 12);

TrackerSnapshot _snap() => TrackerSnapshot(
      sources: const <String>['Fitbit'],
      workouts: <TrackerWorkout>[
        TrackerWorkout(
          id: 'w1',
          type: 'Running',
          start: DateTime(2026, 11, 24, 7),
          end: DateTime(2026, 11, 24, 7, 45),
          minutes: 45,
          distanceKm: 6.2,
          avgHeartRate: 148,
          source: 'Fitbit',
          sourceId: 'com.fitbit.FitbitMobile',
        ),
        TrackerWorkout(
          id: 'mine',
          type: 'Strength training',
          start: DateTime(2026, 11, 24, 18),
          end: DateTime(2026, 11, 24, 19),
          minutes: 60,
          source: 'Gym Days',
          sourceId: 'io.devartel.opengym',
        ),
      ],
      days: <TrackerDay>[
        TrackerDay(date: DateTime(2026, 11, 24), sleepMinutes: 440, restingHeartRate: 52, steps: 8000, activeEnergyKcal: 500),
      ],
    );

({TrackerSync sync, FakeTrackerSource source, FakeConvexClient client, InMemoryTrackerPrefs prefs}) _make({
  bool readOn = true,
  bool connected = true,
  TrackerSnapshot? snapshot,
}) {
  final FakeTrackerSource source = FakeTrackerSource(snapshot: snapshot ?? _snap());
  final FakeConvexClient client = FakeConvexClient();
  final InMemoryTrackerPrefs prefs = InMemoryTrackerPrefs(TrackerPrefsState(readOn: readOn));
  final TrackerSync sync = TrackerSync(
    source: source,
    client: client,
    prefs: prefs,
    isConnected: () => connected,
    now: () => _clock,
  );
  return (sync: sync, source: source, client: client, prefs: prefs);
}

void main() {
  setUp(() => _clock = DateTime(2026, 11, 25, 12));

  test('the payload leaves out missing values and uses a date string', () {
    expect(trackerDayJson(TrackerDay(date: DateTime(2026, 11, 4), steps: 10)), <String, dynamic>{'date': '2026-11-04', 'steps': 10});
    final Map<String, dynamic> w = trackerWorkoutJson(_snap().workouts.first);
    expect(w['workoutId'], 'w1');
    expect(w['startedAt'], DateTime(2026, 11, 24, 7).millisecondsSinceEpoch);
    expect(w.containsKey('energyKcal'), isFalse);
  });

  test('off by default: nothing is read and nothing is sent', () async {
    final m = _make(readOn: false);
    await m.sync.load();
    expect(await m.sync.sync(force: true), SyncOutcome.off);
    expect(m.source.readCalls, 0);
    expect(m.client.trackerSyncs, isEmpty);
  });

  test('on: reads 14 days, sends days and workouts without the app\'s own, and remembers the time', () async {
    final m = _make();
    await m.sync.load();
    expect(await m.sync.sync(), SyncOutcome.sent);
    expect(m.client.trackerSyncs, hasLength(1));
    final sent = m.client.trackerSyncs.single;
    expect(sent.workouts.map((TrackerWorkout w) => w.id), <String>['w1']);
    expect(sent.days, hasLength(1));
    expect(m.sync.state.lastSyncAt, _clock);
    expect(m.sync.state.lastDays, 1);
    expect(m.sync.state.lastWorkouts, 1);
    expect(m.prefs.state.lastSyncAt, _clock);
  });

  test('the window is 14 days back, today included', () async {
    final m = _make();
    await m.sync.load();
    DateTime? from;
    final FakeTrackerSource spy = _Spy(onRead: (DateTime f) => from = f);
    final TrackerSync s = TrackerSync(
      source: spy,
      client: m.client,
      prefs: InMemoryTrackerPrefs(const TrackerPrefsState(readOn: true)),
      isConnected: () => true,
      now: () => _clock,
    );
    await s.load();
    await s.sync();
    expect(from, DateTime(2026, 11, 12));
  });

  test('automatic syncs keep an interval; the button does not', () async {
    final m = _make();
    await m.sync.load();
    await m.sync.sync();
    _clock = _clock.add(const Duration(minutes: 5));
    expect(await m.sync.sync(), SyncOutcome.skipped);
    expect(m.source.readCalls, 1);
    expect(await m.sync.sync(force: true), SyncOutcome.sent);
    expect(m.source.readCalls, 2);
    _clock = _clock.add(const Duration(minutes: 16));
    expect(await m.sync.sync(), SyncOutcome.sent);
    expect(m.source.readCalls, 3);
  });

  test('offline is silent and sends nothing; a failing server never throws', () async {
    final m = _make(connected: false);
    await m.sync.load();
    expect(await m.sync.sync(force: true), SyncOutcome.offline);
    expect(m.source.readCalls, 0);

    final m2 = _make();
    await m2.sync.load();
    m2.client.online = false;
    expect(await m2.sync.sync(force: true), SyncOutcome.failed);
    expect(m2.sync.busy, isFalse);
    expect(m2.sync.state.lastSyncAt, isNull);

    final m3 = _make();
    await m3.sync.load();
    m3.source.error = StateError('plugin');
    expect(await m3.sync.sync(force: true), SyncOutcome.failed);
  });

  test('permission refused and no store are reported, not thrown', () async {
    final m = _make();
    await m.sync.load();
    m.source.error = const TrackerPermissionException();
    expect(await m.sync.sync(force: true), SyncOutcome.noPermission);
    m.source.error = null;
    m.source.isAvailable = false;
    expect(await m.sync.sync(force: true), SyncOutcome.unavailable);
    expect(m.client.trackerSyncs, isEmpty);
  });

  test('an empty phone sends nothing but notes the time', () async {
    final m = _make(snapshot: const TrackerSnapshot());
    await m.sync.load();
    expect(await m.sync.sync(force: true), SyncOutcome.nothing);
    expect(m.client.trackerSyncs, isEmpty);
    expect(m.sync.state.lastSyncAt, _clock);
  });

  test('the switch asks for permission, then sends; it stays off when permission fails', () async {
    final m = _make(readOn: false);
    await m.sync.load();
    m.source.connectResult = false;
    await m.sync.setReadOn(true);
    expect(m.sync.state.readOn, isFalse);
    expect(m.sync.lastOutcome, SyncOutcome.noPermission);

    m.source.connectResult = true;
    await m.sync.setReadOn(true);
    expect(m.source.connectCalls, 2);
    expect(m.sync.state.readOn, isTrue);
    expect(m.prefs.state.readOn, isTrue);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(m.client.trackerSyncs, hasLength(1));

    await m.sync.setReadOn(false);
    expect(m.sync.state.readOn, isFalse);
    expect(await m.sync.sync(force: true), SyncOutcome.off);
  });

  test('a phone with no store: the switch stays off', () async {
    final m = _make(readOn: false);
    m.source.isAvailable = false;
    await m.sync.load();
    await m.sync.setReadOn(true);
    expect(m.sync.state.readOn, isFalse);
    expect(m.sync.lastOutcome, SyncOutcome.unavailable);
  });

  test('a send in progress is not started twice', () async {
    final m = _make();
    await m.sync.load();
    final Future<SyncOutcome> a = m.sync.sync(force: true);
    final SyncOutcome b = await m.sync.sync(force: true);
    expect(b, SyncOutcome.skipped);
    expect(await a, SyncOutcome.sent);
    expect(m.client.trackerSyncs, hasLength(1));
  });

  test('ConvexCallException from the server is swallowed', () async {
    final m = _make();
    await m.sync.load();
    m.client.failNext = const ConvexCallException('nope');
    expect(await m.sync.sync(force: true), SyncOutcome.failed);
  });
}

class _Spy extends FakeTrackerSource {
  _Spy({required this.onRead}) : super(snapshot: const TrackerSnapshot());

  final void Function(DateTime from) onRead;

  @override
  Future<TrackerSnapshot> read({required DateTime from, required DateTime to}) {
    onRead(from);
    return super.read(from: from, to: to);
  }
}
