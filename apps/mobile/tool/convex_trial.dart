// ignore_for_file: avoid_print
// End-to-end check of the app's Convex gateway against a deployment.
// Uses the SAME class the app uses (DartvexConvexClient), not raw dartvex.
//
// Run:
//   CONVEX_URL=https://<name>.convex.cloud OPENGYM_TOKEN=... \
//     dart run tool/convex_trial.dart
//
// It subscribes to the "Upper" plan, the dashboard and the sessions, saves ONE
// session marked `trial-<ts>` (type "Trial", one failed set), waits for the
// live update, removes that same session and waits for the removal. It never
// touches any other row. Never prints the token.
import 'dart:async';
import 'dart:io';

import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';

Future<T> _next<T>(Stream<T> s, bool Function(T) ok, String what) {
  return s.firstWhere(ok).timeout(const Duration(seconds: 20),
      onTimeout: () => throw StateError('timed out waiting for $what'));
}

Future<void> main() async {
  final String? url = Platform.environment['CONVEX_URL'];
  final String? token = Platform.environment['OPENGYM_TOKEN'];
  if (url == null || token == null || url.isEmpty || token.isEmpty) {
    stderr.writeln('Set CONVEX_URL and OPENGYM_TOKEN.');
    exit(2);
  }
  final ConvexClient c = DartvexConvexClient.connect(url: url, token: token);
  final StreamSubscription<ConvexLink> link =
      c.connection.listen((ConvexLink l) => print('link: ${l.name}'));

  print('access check: ${(await c.checkAccess()).name}');

  final Stored<Plan> plan = await _next(c.watchNextPlan('Upper'), (_) => true, 'the Upper plan');
  print('plan Upper: source=${plan.source} stored=${plan.stored} '
      'exercises=${plan.value.exercises.length}');

  for (final int days in <int>[7, 30]) {
    final Stored<Dashboard> d = await _next(c.watchDashboard(days), (_) => true, 'dashboard $days');
    print('dashboard $days days: source=${d.source} stored=${d.stored} '
        'modules=${d.value.modules.length}');
  }

  final Stored<List<Prediction>> p = await _next(c.watchPredictions(), (_) => true, 'predictions');
  print('predictions: source=${p.source} stored=${p.stored} '
      'first=${p.value.isEmpty ? '-' : p.value.first.type}');

  final List<Session> before =
      await _next(c.watchRecentSessions(limit: 200), (_) => true, 'sessions');
  print('recent sessions before: ${before.length} (none will be touched)');

  final String id = 'trial-${DateTime.now().millisecondsSinceEpoch}';
  final int now = DateTime.now().millisecondsSinceEpoch;
  final Session trial = Session(
    id: id,
    kind: 'gym',
    type: 'Trial',
    startedAt: now - 60000,
    endedAt: now,
    note: 'Gateway end-to-end trial. Safe to delete.',
    exercises: <Exercise>[
      Exercise(id: 'e1', name: 'Trial lift', sets: <SetEntry>[
        SetEntry(reps: 6, kg: 70, failed: true, done: true, at: now - 30000),
      ]),
    ],
  );

  final Stopwatch sw = Stopwatch()..start();
  final Future<List<Session>> appeared = _next(c.watchRecentSessions(limit: 200),
      (List<Session> l) => l.any((Session s) => s.id == id), 'the trial session to appear');
  await c.saveSession(trial);
  final int saveMs = sw.elapsedMilliseconds;
  final Session back = (await appeared).firstWhere((Session s) => s.id == id);
  print('saved $id (call ${saveMs}ms, live update ${sw.elapsedMilliseconds}ms): '
      'type=${back.type} failed=${back.exercises.single.sets.single.failed}');

  // Resending the same write changes nothing (idempotent).
  await c.saveSession(trial);
  print('resend: ok');

  final Stored<Review?> review =
      await _next(c.watchReview(id), (Stored<Review?> r) => r.value != null, 'the review');
  print('review: source=${review.source} stored=${review.stored}');

  final Future<List<Session>> gone = _next(c.watchRecentSessions(limit: 200),
      (List<Session> l) => !l.any((Session s) => s.id == id), 'removal');
  await c.removeSession(id);
  final List<Session> after = await gone;
  print('removed $id; recent sessions after: ${after.length}');

  // A wrong token is told apart, with a plain message and no stack trace.
  final ConvexClient bad = DartvexConvexClient.connect(url: url, token: 'wrong');
  print('wrong token check: ${(await bad.checkAccess()).name}');
  try {
    await bad.removeSession('trial-none');
    print('wrong token command: NO ERROR (unexpected)');
  } on ConvexCallException catch (e) {
    print('wrong token command: kind=${e.kind.name} message="${e.message}"');
  }
  await bad.dispose();

  await link.cancel();
  await c.dispose();
  print('done');
  exit(0);
}
