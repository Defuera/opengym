import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/models.dart';
import 'package:opengym/stores/coach_store.dart';
import 'package:opengym/stores/import_store.dart';

import 'support/fake_convex_client.dart';

Future<(FakeConvexClient, CoachStore, String)> _open() async {
  final FakeConvexClient fake = FakeConvexClient();
  final CoachStore coach = CoachStore(client: fake, isConnected: () => true)..start();
  final String? id = await coach.createThread('Knee');
  await coach.openThread(id!);
  await pump();
  return (fake, coach, id);
}

void main() {
  test('threads are live and carry the reply status', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    expect(coach.threads.single.title, 'Knee');
    expect(coach.threads.single.thinking, isFalse);
    await coach.send('hi');
    await pump();
    expect(coach.threads.single.thinking, isTrue);
    expect(fake.calls.first, startsWith('createThread:'));
    await coach.deleteThread(id);
    await pump();
    expect(coach.threads, isEmpty);
    expect(coach.currentId, isNull);
  });

  test('optimistic send, then the server echo gives one message', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    fake.sendGate = Completer<void>();
    final Future<bool> sent = coach.send('What now?');
    await pump();
    expect(coach.messages, hasLength(1)); // shown before the server has it
    expect(coach.messages.single.text, 'What now?');
    expect(coach.messages.single.mine, isTrue);
    fake.sendGate!.complete();
    expect(await sent, isTrue);
    await pump();
    expect(coach.messages, hasLength(1)); // the server copy replaced it
    expect(fake.serverMessages[id], hasLength(1));
    expect(coach.messages.single.id, fake.serverMessages[id]!.single.id);
  });

  test('thinking, then the answer arrives through the subscription', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    await coach.send('Focus?');
    await pump();
    expect(coach.thinking, isTrue);
    fake.coachAnswers(id, 'Focus on rows.');
    await pump();
    expect(coach.thinking, isFalse);
    expect(coach.messages.map((Message m) => m.role), <String>['user', 'assistant']);
  });

  test('items the coach extracted show as chips after the answer', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    await coach.send('My knee hurts on squats');
    await pump();
    fake.serverChanged(() {
      fake.serverGoals['g1'] = Goal(
          id: 'g1',
          title: 'Squat 100 kg',
          kind: 'lift',
          status: 'active',
          source: 'ai',
          createdAt: 5000000,
          threadId: id);
      fake.serverGoals['old'] = Goal(
          id: 'old',
          title: 'Old goal',
          kind: 'custom',
          status: 'active',
          source: 'ai',
          createdAt: 1,
          threadId: id);
      fake.serverContext['c1'] = ContextItem(
          id: 'c1', text: 'Knee pain', topic: 'injury', active: true, source: 'ai', createdAt: 5000000, threadId: id);
    });
    fake.coachAnswers(id, 'Noted.');
    await pump();
    expect(coach.saved, <String>['Goal: Squat 100 kg', 'Knee pain']);
  });

  test('failed shows the error and retry reuses the same message id', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    await coach.send('Plan?');
    await pump();
    final String sentId = fake.serverMessages[id]!.single.id;
    fake.coachFails(id, 'The coach could not answer: timeout');
    await pump();
    expect(coach.retryReason, contains('timeout'));
    fake.calls.clear();
    await coach.retry();
    expect(fake.calls, <String>['sendMessage:$sentId']);
    expect(fake.serverMessages[id], hasLength(1));
  });

  test('a send that fails keeps the message and retry reuses its id', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    fake.failNext = const ConvexCallException.unreachable();
    expect(await coach.send('Hello'), isTrue);
    expect(coach.messages.single.text, 'Hello'); // still shown
    expect(coach.retryReason, isNotNull);
    expect(fake.serverMessages[id], isNull);
    final String messageId = coach.messages.single.id;
    await coach.retry();
    await pump();
    expect(fake.calls.last, 'sendMessage:$messageId');
    expect(coach.messages, hasLength(1));
    expect(coach.retryReason, isNull);
  });

  test('files upload first, then the message is sent with their ids', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    coach.addAttachment(UploadItem(path: '', name: 'log.txt', bytes: List<int>.filled(1000, 65)));
    coach.addAttachment(const UploadItem(path: '', name: 'b.csv', bytes: <int>[1, 2]));
    fake.calls.clear();
    await coach.send('See these');
    await pump();
    expect(fake.calls.map((String c) => c.split(':').first),
        <String>['uploadFile', 'uploadFile', 'sendMessage']);
    final Message m = fake.serverMessages[id]!.single;
    expect(m.fileIds.toSet(), fake.serverFiles.keys.toSet());
    expect(fake.serverFiles.values.first.mime, 'text/plain');
    expect(coach.attachments, isEmpty);
  });

  test('a failed upload sends nothing and retry does not upload twice', () async {
    final (FakeConvexClient fake, CoachStore coach, String id) = await _open();
    coach.addAttachment(const UploadItem(path: '', name: 'a.txt', bytes: <int>[1]));
    fake.failUpload = const ConvexCallException.unreachable();
    await coach.send('x');
    expect(fake.serverMessages[id], isNull);
    expect(coach.retryReason, isNotNull);
    await coach.retry();
    await pump();
    expect(fake.calls.where((String c) => c.startsWith('uploadFile')), hasLength(1));
    expect(fake.serverMessages[id]!.single.fileIds, hasLength(1));
  });

  test('offline: send is refused, nothing is queued', () async {
    final FakeConvexClient fake = FakeConvexClient();
    bool on = true;
    final CoachStore coach = CoachStore(client: fake, isConnected: () => on)..start();
    final String? id = await coach.createThread('T');
    await coach.openThread(id!);
    on = false;
    fake.calls.clear();
    expect(await coach.send('hello'), isFalse);
    expect(coach.error, chatOfflineMessage);
    expect(coach.messages, isEmpty);
    expect(fake.calls, isEmpty);
  });

  test('file import: upload, start, live progress to done, then undo', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final ImportStore s = ImportStore(client: fake)..watchPast();
    String? undone;
    s.onUndone = (String id) => undone = id;
    s.add(const UploadItem(path: '', name: 'history.csv', bytes: <int>[1, 2, 3]));
    s.add(const UploadItem(path: '', name: 'shot.png', bytes: <int>[4]));
    await s.start();
    expect(fake.calls.map((String c) => c.split(':').first),
        <String>['uploadFile', 'uploadFile', 'startImport']);
    expect(s.picked, isEmpty);
    expect(s.job!.running, isTrue); // shown at once
    await pump();
    final String id = fake.serverImports.keys.single;
    expect(s.job!.total, 2);
    fake.importProgress(id, processed: 1, counts: const ImportCounts(sessions: 5));
    await pump();
    expect(s.job!.processed, 1);
    expect(s.job!.counts.sessions, 5);
    expect(s.busy, isTrue);
    fake.importProgress(id,
        processed: 2,
        counts: const ImportCounts(sessions: 9, goals: 1),
        notes: <String>['Skipped one row'],
        status: 'done');
    await pump();
    expect(s.job!.finished, isTrue);
    expect(s.job!.notes, <String>['Skipped one row']);
    expect(s.busy, isFalse);
    expect(await s.undo(id), isTrue);
    await pump();
    expect(undone, id);
    expect(fake.calls.last, 'removeImport:$id');
    expect(s.job, isNull);
    expect(s.past, isEmpty);
    s.dispose();
  });

  test('a failed import job shows as failed', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final ImportStore s = ImportStore(client: fake)..watchPast();
    s.add(const UploadItem(path: '', name: 'a.csv', bytes: <int>[1]));
    await s.start();
    await pump();
    fake.importProgress(fake.serverImports.keys.single, status: 'failed', notes: <String>['No data']);
    await pump();
    expect(s.job!.failed, isTrue);
    expect(s.busy, isFalse);
  });

  test('an upload error keeps the files and retry makes no second import', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final ImportStore s = ImportStore(client: fake)..watchPast();
    s.add(const UploadItem(path: '', name: 'a.csv', bytes: <int>[1]));
    fake.failUpload = const ConvexCallException.unreachable();
    await s.start();
    expect(s.error, isNotNull);
    expect(s.picked, hasLength(1));
    await s.start();
    await pump();
    expect(fake.serverImports, hasLength(1));
  });
}
