import 'dart:async';

import 'package:dartvex/dartvex.dart' as cx;
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';

class _Caller implements cx.ConvexFunctionCaller {
  final StreamController<cx.QueryResult> results = StreamController<cx.QueryResult>.broadcast();
  final List<Map<String, dynamic>> mutations = <Map<String, dynamic>>[];
  String? subscribed;
  Object? answer;

  @override
  cx.ConvexSubscription subscribe(String name, [Map<String, dynamic> args = const <String, dynamic>{}]) {
    subscribed = name;
    return cx.ConvexSubscription(stream: results.stream, onCancel: () async {});
  }

  @override
  Future<dynamic> mutate(String name, [Map<String, dynamic> args = const <String, dynamic>{}, cx.OptimisticUpdate? optimisticUpdate]) async {
    mutations.add(<String, dynamic>{'fn': name, ...args});
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DartvexConvexClient _client(_Caller c) =>
    DartvexConvexClient(caller: c, token: 't', connectionStates: const Stream<ConvexLink>.empty());

void main() {
  test('a thread about a program is created with the contract arguments', () async {
    final _Caller c = _Caller();
    await _client(c).createThread(threadId: 't1', about: const ThreadAbout());
    await _client(c).createThread(threadId: 't2', about: const ThreadAbout(id: 'prog'));
    await _client(c).createThread(threadId: 't3');
    expect(c.mutations[0], <String, dynamic>{
      'fn': 'commands/threads:create',
      'token': 't',
      'threadId': 't1',
      'about': <String, dynamic>{'kind': 'program'},
    });
    expect((c.mutations[1]['about'] as Map<String, dynamic>)['id'], 'prog');
    expect(c.mutations[2].containsKey('about'), isFalse);
  });

  test('accept returns the program id; decline, setStatus and remove use their functions', () async {
    final _Caller c = _Caller()..answer = <String, dynamic>{'programId': 'prog-5'};
    final DartvexConvexClient cl = _client(c);
    expect(await cl.acceptProposal('p1'), 'prog-5');
    await cl.declineProposal('p1');
    await cl.setProgramStatus('prog-5', 'paused');
    await cl.removeProgram('prog-5');
    expect(c.mutations.map((Map<String, dynamic> m) => m['fn']), <Object?>[
      'commands/proposals:accept',
      'commands/proposals:decline',
      'commands/programs:setStatus',
      'commands/programs:remove',
    ]);
    expect(c.mutations[2]['status'], 'paused');
    expect(c.mutations[3]['programId'], 'prog-5');
  });

  test('requestStart with feedback and previousPlan sends both with the name', () async {
    final _Caller c = _Caller();
    await _client(c).requestStart(
      requestId: 'r1',
      name: 'Gym',
      feedback: 'no step-ups',
      previousPlan: <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Squat',
          'sets': <Map<String, dynamic>>[
            <String, dynamic>{'reps': 8, 'kg': 60.0, 'max': false},
          ],
        },
      ],
    );
    final Map<String, dynamic> m = c.mutations.single;
    expect(m['fn'], 'commands/start:request');
    expect(m['name'], 'Gym');
    expect(m['feedback'], 'no step-ups');
    expect(m.containsKey('previousRequestId'), isFalse);
    expect((m['previousPlan'] as List<dynamic>).length, 1);
  });

  test('a saved program session carries programId, programWeek, programSlot and programKey', () async {
    final _Caller c = _Caller();
    await _client(c).saveSession(Session(
      id: 's1',
      kind: 'gym',
      type: 'Gym',
      startedAt: 1,
      endedAt: 2,
      program: const ProgramLink(programId: 'prog', week: 2, slot: 1, key: 'B'),
    ));
    final Map<String, dynamic> s = c.mutations.single['session'] as Map<String, dynamic>;
    expect(s['programId'], 'prog');
    expect(s['programWeek'], 2);
    expect(s['programSlot'], 1);
    expect(s['programKey'], 'B');
  });

  test('the program streams use the contract query names', () async {
    final _Caller c = _Caller();
    final DartvexConvexClient cl = _client(c);
    final StreamSubscription<List<Program>> a = cl.watchPrograms().listen((_) {});
    expect(c.subscribed, 'queries/programs:list');
    final StreamSubscription<List<Proposal>> b = cl.watchThreadProposals('t1').listen((_) {});
    expect(c.subscribed, 'queries/proposals:forThread');
    await a.cancel();
    await b.cancel();
  });
}
