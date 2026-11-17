import 'dart:async';

import 'package:dartvex/dartvex.dart' as cx;
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';

class _FakeCaller implements cx.ConvexFunctionCaller {
  final StreamController<cx.QueryResult> results = StreamController<cx.QueryResult>.broadcast();
  final List<Map<String, dynamic>> mutations = <Map<String, dynamic>>[];
  Map<String, dynamic>? subscribeArgs;
  String? subscribeName;
  Object? mutateError;
  Object? queryError;

  @override
  cx.ConvexSubscription subscribe(String name,
      [Map<String, dynamic> args = const <String, dynamic>{}]) {
    subscribeName = name;
    subscribeArgs = args;
    return cx.ConvexSubscription(stream: results.stream, onCancel: () async {});
  }

  @override
  Future<dynamic> mutate(String name,
      [Map<String, dynamic> args = const <String, dynamic>{},
      cx.OptimisticUpdate? optimisticUpdate]) async {
    final Object? e = mutateError;
    if (e != null) {
      throw e;
    }
    mutations.add(<String, dynamic>{'name': name, ...args});
  }

  @override
  Future<dynamic> query(String name,
      [Map<String, dynamic> args = const <String, dynamic>{}]) async {
    final Object? e = queryError;
    if (e != null) {
      throw e;
    }
    return <dynamic>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DartvexConvexClient _client(_FakeCaller fake) => DartvexConvexClient(
      caller: fake,
      token: 't',
      connectionStates: const Stream<ConvexLink>.empty(),
    );

const Map<String, dynamic> _doc = <String, dynamic>{
  '_id': 'x',
  'sessionId': 'a1',
  'kind': 'gym',
  'type': 'Gym',
  'focus': 'Push',
  'startedAt': 1000.0,
  'endedAt': 2000.0,
  'exercises': <dynamic>[
    <String, dynamic>{
      'name': 'Bench press',
      'sets': <dynamic>[
        <String, dynamic>{'reps': 6.0, 'kg': 70.0, 'max': false, 'failed': true},
      ],
    },
  ],
  'source': 'app',
};

void main() {
  test('watchRecentSessions decodes, keeps the failed flag, sends the token', () async {
    final _FakeCaller fake = _FakeCaller();
    final List<Object> events = <Object>[];
    final StreamSubscription<List<Session>> sub =
        _client(fake).watchRecentSessions(limit: 5).listen(events.add, onError: events.add);
    await Future<void>.delayed(Duration.zero);
    expect(fake.subscribeName, 'queries/sessions:recent');
    expect(fake.subscribeArgs, <String, dynamic>{'token': 't', 'limit': 5});
    fake.results.add(const cx.QuerySuccess(<dynamic>[_doc]));
    await Future<void>.delayed(Duration.zero);
    final Session s = (events[0] as List<Session>).single;
    expect(s.id, 'a1');
    expect(s.endedAt, 2000);
    expect(s.exercises.single.sets.single.failed, isTrue);
    await sub.cancel();
  });

  test('a stream error shows the Convex data, never the raw message', () async {
    final _FakeCaller fake = _FakeCaller();
    final List<Object> events = <Object>[];
    final StreamSubscription<List<Goal>> sub =
        _client(fake).watchGoals().listen((_) {}, onError: events.add);
    await Future<void>.delayed(Duration.zero);
    fake.results
        .add(const cx.QueryError('Server Error\n  at handler (stack...)', data: 'unauthorized'));
    fake.results.add(const cx.QueryError('Server Error\n  at handler (stack...)'));
    await Future<void>.delayed(Duration.zero);
    final ConvexCallException a = events[0] as ConvexCallException;
    expect(a.unauthorized, isTrue);
    expect(a.message, isNot(contains('stack')));
    final ConvexCallException b = events[1] as ConvexCallException;
    expect(b.message, isNot(contains('stack')));
    expect(b.kind, ConvexFailure.transient);
    await sub.cancel();
  });

  test('read models decode with stored and source', () async {
    final _FakeCaller fake = _FakeCaller();
    final List<Stored<List<Prediction>>> got = <Stored<List<Prediction>>>[];
    final StreamSubscription<Stored<List<Prediction>>> sub =
        _client(fake).watchPredictions().listen(got.add);
    await Future<void>.delayed(Duration.zero);
    fake.results.add(const cx.QuerySuccess(<String, dynamic>{
      'predictions': <dynamic>[
        <String, dynamic>{'kind': 'gym', 'type': 'Gym', 'focus': 'Pull', 'reason': 'Due'}
      ],
      'source': 'rules',
      'stored': false,
    }));
    await Future<void>.delayed(Duration.zero);
    expect(got.single.stored, isFalse);
    expect(got.single.source, 'rules');
    expect(got.single.value.single.type, 'Gym');
    expect(got.single.value.single.focus, 'Pull');
    await sub.cancel();
  });

  test('saveSession sends the contract shape with sessionId and failed', () async {
    final _FakeCaller fake = _FakeCaller();
    await _client(fake).saveSession(Session(
        id: 's9',
        kind: 'gym',
        type: 'Gym',
        focus: 'Push',
        startedAt: 1,
        endedAt: 2,
        exercises: <Exercise>[
          Exercise(id: 'e', name: 'Bench', sets: <SetEntry>[
            SetEntry(reps: 6, kg: 70, failed: true, done: true),
          ]),
        ]));
    final Map<String, dynamic> m = fake.mutations.single;
    expect(m['name'], 'commands/sessions:save');
    final Map<String, dynamic> s = m['session'] as Map<String, dynamic>;
    expect(s['sessionId'], 's9');
    expect(s['focus'], 'Push');
    expect(s.containsKey('id'), isFalse);
    final List<dynamic> sets =
        ((s['exercises'] as List<dynamic>).single as Map)['sets'] as List<dynamic>;
    expect((sets.single as Map)['failed'], isTrue);
  });

  test('a refused command shows the error data, not the stack trace', () async {
    final _FakeCaller fake = _FakeCaller()
      ..mutateError = const cx.ConvexException(
        'Server Error  Uncaught ConvexError: goal not found\n at handler (file:1)',
        data: 'goal not found: g1',
      );
    try {
      await _client(fake).updateGoal('g1', const GoalPatch(status: 'done'));
      fail('should throw');
    } on ConvexCallException catch (e) {
      expect(e.message, 'goal not found: g1');
      expect(e.rejected, isTrue);
    }
    fake.mutateError = const cx.ConvexException('connection lost', retryable: true);
    try {
      await _client(fake).removeGoal('g1');
      fail('should throw');
    } on ConvexCallException catch (e) {
      expect(e.kind, ConvexFailure.transient);
      expect(e.message, isNot(contains('connection lost')));
    }
  });

  test('goal and context commands use the contract names and ids', () async {
    final _FakeCaller fake = _FakeCaller();
    final DartvexConvexClient c = _client(fake);
    await c.createGoal(goalId: 'g1', title: 'Bench 100', kind: 'strength', targetKg: 100);
    await c.updateGoal('g1', const GoalPatch(status: 'done'));
    await c.createContext(itemId: 'c1', text: 'Bad knee', topic: 'injury');
    await c.updateContext('c1', const ContextPatch(active: false));
    await c.removeImport('imp1');
    expect(fake.mutations.map((Map<String, dynamic> m) => m['name']).toList(), <String>[
      'commands/goals:create',
      'commands/goals:update',
      'commands/context:create',
      'commands/context:update',
      'commands/imports:remove',
    ]);
    expect(fake.mutations[0]['goalId'], 'g1');
    expect(fake.mutations[0].containsKey('exercise'), isFalse);
    expect(fake.mutations[1]['status'], 'done');
    expect(fake.mutations[3]['active'], isFalse);
  });

  test('checkAccess tells a wrong token from an unreachable server', () async {
    final _FakeCaller fake = _FakeCaller();
    final DartvexConvexClient c = _client(fake);
    expect(await c.checkAccess(), AccessStatus.ok);
    fake.queryError = const cx.ConvexException('x', data: 'unauthorized');
    expect(await c.checkAccess(), AccessStatus.unauthorized);
    fake.queryError = StateError('socket closed');
    expect(await c.checkAccess(), AccessStatus.unreachable);
  });
}
