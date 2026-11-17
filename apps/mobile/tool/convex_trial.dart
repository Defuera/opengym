// ignore_for_file: avoid_print
// End-to-end check of the app's Convex gateway against a deployment.
// Uses the SAME class the app uses (DartvexConvexClient), not raw dartvex.
//
// Run:
//   CONVEX_URL=https://<name>.convex.cloud OPENGYM_TOKEN=... \
//     dart run tool/convex_trial.dart
//
// Part 1 subscribes to the "Upper" plan, the dashboard and the sessions. With
// TRIAL_SESSION_WRITE=1 it also saves ONE session marked `trial-<ts>`, waits
// for the live update and removes that same session.
//
// Part 2 is the chat round trip: it creates a thread titled "Trial", sends one
// message, waits for the coach answer on the subscription, uploads a 1 kB
// text file, reads its URL, and removes ONLY what it made (the thread and its
// messages, goals and notes tagged with that thread, the test file). It prints
// row counts before and after. It never empties a table. Never prints the token.
import 'dart:async';
import 'dart:io';

import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';

Future<T> _next<T>(Stream<T> s, bool Function(T) ok, String what,
    [Duration wait = const Duration(seconds: 20)]) {
  return s.firstWhere(ok).timeout(wait,
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

  final Stored<Plan> plan = await _next(c.watchNextPlan(focus: 'Upper'), (_) => true, 'the Upper plan');
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

  final Map<String, int> countsBefore = await _counts(url, token);
  print('counts before: $countsBefore');

  if (Platform.environment['TRIAL_SESSION_WRITE'] == '1') {
    await _sessionRoundTrip(c);
  } else {
    print('session write skipped (set TRIAL_SESSION_WRITE=1 to run it)');
  }

  await _chatRoundTrip(c);
  await _fileRoundTrip(c);

  final Map<String, int> countsAfter = await _counts(url, token);
  print('counts after:  $countsAfter');
  print(countsAfter.toString() == countsBefore.toString()
      ? 'counts unchanged: OK'
      : 'COUNTS DIFFER: check by hand');

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

/// Counts rows through a FRESH connection: one connection can replay a cached
/// first value for the same query, which hides a removal.
Future<Map<String, int>> _counts(String url, String token) async {
  final ConvexClient c = DartvexConvexClient.connect(url: url, token: token);
  try {
    return await _countsOn(c);
  } finally {
    await c.dispose();
  }
}

Future<Map<String, int>> _countsOn(ConvexClient c) async {
  final List<Thread> threads = await _next(c.watchThreads(), (_) => true, 'threads');
  int messages = 0;
  for (final Thread t in threads) {
    messages += (await _next(c.watchMessages(t.id), (_) => true, 'messages')).length;
  }
  return <String, int>{
    'sessions': (await _next(c.watchRecentSessions(limit: 1000), (_) => true, 'sessions')).length,
    'goals': (await _next(c.watchGoals(), (_) => true, 'goals')).length,
    'context': (await _next(c.watchContext(), (_) => true, 'context')).length,
    'imports': (await _next(c.watchImports(), (_) => true, 'imports')).length,
    'threads': threads.length,
    'messages': messages,
  };
}

Future<void> _chatRoundTrip(ConvexClient c) async {
  final String threadId = 'trial-thread-${DateTime.now().millisecondsSinceEpoch}';
  final String messageId = 'trial-msg-${DateTime.now().millisecondsSinceEpoch}';
  print('--- chat round trip ---');
  await c.createThread(threadId: threadId, title: 'Trial');
  final Thread t = (await _next(c.watchThreads(),
          (List<Thread> l) => l.any((Thread x) => x.id == threadId), 'the thread'))
      .firstWhere((Thread x) => x.id == threadId);
  print('thread created: title="${t.title}" status=${t.status}');
  try {
    final Stopwatch sw = Stopwatch()..start();
    final Future<List<Message>> answered = _next(
        c.watchMessages(threadId),
        (List<Message> l) => l.any((Message m) => !m.mine),
        'the assistant message',
        const Duration(seconds: 120));
    await c.sendMessage(
        threadId: threadId,
        messageId: messageId,
        text: 'What should I focus on in my next upper session?');
    print('send call returned after ${sw.elapsedMilliseconds}ms');
    final List<Message> list = await answered;
    final int ms = sw.elapsedMilliseconds;
    final Message a = list.firstWhere((Message m) => !m.mine);
    print('answer: length=${a.text.length} chars, sources=${a.sources}, '
        'send to answer=${ms}ms, messages in thread=${list.length}');
    final Thread idle = (await _next(
            c.watchThreads(),
            (List<Thread> l) => l.any((Thread x) => x.id == threadId && x.status != 'thinking'),
            'the thread to leave thinking',
            const Duration(seconds: 120)))
        .firstWhere((Thread x) => x.id == threadId);
    print('thread status after answer: ${idle.status}');
    // The coach may save goals or notes from the message a few seconds later.
    await Future<void>.delayed(const Duration(seconds: 25));
  } finally {
    final List<Goal> goals = await _next(c.watchGoals(), (_) => true, 'goals');
    for (final Goal g in goals.where((Goal g) => g.threadId == threadId)) {
      print('removing goal tagged with the trial thread: "${g.title}"');
      await c.removeGoal(g.id);
    }
    final List<ContextItem> ctx = await _next(c.watchContext(), (_) => true, 'context');
    for (final ContextItem i in ctx.where((ContextItem i) => i.threadId == threadId)) {
      print('removing note tagged with the trial thread: "${i.text}"');
      await c.removeContext(i.id);
    }
    await c.removeThread(threadId);
    await Future<void>.delayed(const Duration(seconds: 3));
    final List<Goal> g2 = await _next(c.watchGoals(), (_) => true, 'goals');
    final List<ContextItem> c2 = await _next(c.watchContext(), (_) => true, 'context');
    final int left = g2.where((Goal g) => g.threadId == threadId).length +
        c2.where((ContextItem i) => i.threadId == threadId).length;
    print('thread removed; tagged items left behind: $left');
  }
}

Future<void> _fileRoundTrip(ConvexClient c) async {
  print('--- file round trip ---');
  final String fileId = 'trial-file-${DateTime.now().millisecondsSinceEpoch}';
  final List<int> bytes = List<int>.generate(1024, (int i) => 97 + i % 26);
  final FileMeta m = await c.uploadFile(
      fileId: fileId, name: 'trial.txt', mime: 'text/plain', bytes: bytes);
  print('registered: name=${m.name} mime=${m.mime} size=${m.size} kind=${m.kind}');
  try {
    final FileLink? l = await c.fileLink(fileId);
    print('url present: ${l?.url != null}');
    final HttpClient h = HttpClient();
    final HttpClientResponse r = await (await h.getUrl(Uri.parse(l!.url!))).close();
    final int got = (await r.fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b))).length;
    print('download: status=${r.statusCode} bytes=$got');
    h.close();
  } finally {
    await c.removeFile(fileId);
    print('file removed; lookup now: ${(await c.fileLink(fileId)) == null ? 'null (gone)' : 'STILL THERE'}');
  }
}

Future<void> _sessionRoundTrip(ConvexClient c) async {
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
}
