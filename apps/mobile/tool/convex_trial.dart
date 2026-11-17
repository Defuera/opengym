// ignore_for_file: avoid_print
// Trial of the dartvex client against the hosted Convex deployment.
// Run: CONVEX_URL=... OPENGYM_TOKEN=... dart run tool/convex_trial.dart
// Never prints the token.
import 'dart:async';
import 'dart:io';

import 'package:dartvex/dartvex.dart';

Future<void> main() async {
  final String? url = Platform.environment['CONVEX_URL'];
  final String? token = Platform.environment['OPENGYM_TOKEN'];
  if (url == null || token == null) {
    stderr.writeln('Set CONVEX_URL and OPENGYM_TOKEN.');
    exit(2);
  }
  final ConvexClient client = ConvexClient(url);
  client.connectionStatus.listen((ConnectionStatus s) =>
      print('link: state=${s.state.name} connected=${s.isConnected} '
          'retries=${s.connectionRetries}'));

  final ConvexSubscription sub = client
      .subscribe('queries/sessions:recent', <String, dynamic>{'token': token});
  final Completer<int> first = Completer<int>();
  final Completer<int> live = Completer<int>();
  final String id = 'trial-${DateTime.now().millisecondsSinceEpoch}';
  final Stopwatch sw = Stopwatch();
  int updates = 0;
  sub.stream.listen((QueryResult r) {
    if (r is QuerySuccess) {
      updates++;
      final List<dynamic> list = r.value as List<dynamic>;
      if (!first.isCompleted) {
        first.complete(list.length);
      } else if (!live.isCompleted &&
          list.any((dynamic e) => (e as Map)['sessionId'] == id)) {
        live.complete(sw.elapsedMilliseconds);
      }
    } else if (r is QueryError) {
      print('subscription error: ${r.message}');
    }
  });

  final int count = await first.future.timeout(const Duration(seconds: 15));
  print('first result: $count sessions');

  final int now = DateTime.now().millisecondsSinceEpoch;
  sw.start();
  await client.mutate('commands/sessions:save', <String, dynamic>{
    'token': token,
    'session': <String, dynamic>{
      'sessionId': id,
      'kind': 'activity',
      'type': 'Trial',
      'startedAt': now,
      'endedAt': now,
      'exercises': <dynamic>[],
      'source': 'app',
    },
  });
  final int mutMs = sw.elapsedMilliseconds;
  print('mutation resolved after $mutMs ms (id $id)');
  final int ms = await live.future.timeout(const Duration(seconds: 15));
  print('live update delivered $ms ms after the mutation call '
      '(no re-query; $updates subscription results seen)');

  try {
    await client
        .query('queries/sessions:recent', <String, dynamic>{'token': 'wrong'});
    print('wrong token: NO ERROR (unexpected)');
  } on ConvexException catch (e) {
    print('wrong token surfaced ConvexException: ${e.message} data=${e.data}');
  }

  if (Platform.environment['TRIAL_REMOVE'] == '1') {
    await client.mutate('commands/sessions:remove',
        <String, dynamic>{'token': token, 'sessionId': id});
    print('removed $id');
  }
  sub.cancel();
  client.dispose();
  print('done');
}
