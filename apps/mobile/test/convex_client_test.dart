import 'dart:async';

import 'package:dartvex/dartvex.dart' as cx;
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';

class _FakeCaller implements cx.ConvexFunctionCaller {
  final StreamController<cx.QueryResult> results =
      StreamController<cx.QueryResult>.broadcast();
  final List<Map<String, dynamic>> mutations = <Map<String, dynamic>>[];
  Map<String, dynamic>? subscribeArgs;

  @override
  cx.ConvexSubscription subscribe(String name,
      [Map<String, dynamic> args = const <String, dynamic>{}]) {
    subscribeArgs = args;
    return cx.ConvexSubscription(stream: results.stream, onCancel: () async {});
  }

  @override
  Future<dynamic> mutate(String name,
      [Map<String, dynamic> args = const <String, dynamic>{},
      cx.OptimisticUpdate? optimisticUpdate]) async {
    mutations.add(<String, dynamic>{'name': name, ...args});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('watchRecentSessions decodes, forwards errors, sends the token',
      () async {
    final _FakeCaller fake = _FakeCaller();
    final DartvexConvexClient c = DartvexConvexClient(
      caller: fake,
      token: 't',
      connectionStates: const Stream<ConvexLink>.empty(),
    );
    final List<Object> events = <Object>[];
    final StreamSubscription<List<Session>> sub =
        c.watchRecentSessions(limit: 5).listen(events.add, onError: events.add);
    await Future<void>.delayed(Duration.zero);
    expect(fake.subscribeArgs, <String, dynamic>{'token': 't', 'limit': 5});
    fake.results.add(const cx.QuerySuccess(<dynamic>[
      <String, dynamic>{
        '_id': 'x',
        'sessionId': 'a1',
        'kind': 'activity',
        'type': 'Run',
        'startedAt': 1000.0,
        'endedAt': 2000.0,
        'exercises': <dynamic>[],
        'source': 'app',
      }
    ]));
    fake.results.add(const cx.QueryError('unauthorized'));
    await Future<void>.delayed(Duration.zero);
    expect((events[0] as List<Session>).single.id, 'a1');
    expect((events[0] as List<Session>).single.endedAt, 2000);
    expect(events[1], isA<ConvexCallException>());
    await sub.cancel();
  });

  test('saveSession sends the contract shape with sessionId', () async {
    final _FakeCaller fake = _FakeCaller();
    final DartvexConvexClient c = DartvexConvexClient(
      caller: fake,
      token: 't',
      connectionStates: const Stream<ConvexLink>.empty(),
    );
    await c.saveSession(Session(
        id: 's9', kind: 'activity', type: 'Run', startedAt: 1, endedAt: 2));
    final Map<String, dynamic> m = fake.mutations.single;
    expect(m['name'], 'commands/sessions:save');
    final Map<String, dynamic> s = m['session'] as Map<String, dynamic>;
    expect(s['sessionId'], 's9');
    expect(s.containsKey('id'), isFalse);
  });
}
