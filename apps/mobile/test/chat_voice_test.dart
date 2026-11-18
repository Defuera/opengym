import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/voice_recorder.dart';
import 'package:opengym/widgets/chat_bubble.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const ValueKey<String> _mic = ValueKey<String>('composer-mic');
const ValueKey<String> _send = ValueKey<String>('composer-send');
const ValueKey<String> _cancel = ValueKey<String>('composer-cancel-record');
const ValueKey<String> _stop = ValueKey<String>('composer-stop-record');
const ValueKey<String> _time = ValueKey<String>('record-time');

Future<(FakeConvexClient, FakeVoiceRecorder, AppDeps)> _open(WidgetTester t,
    {bool connected = true, FakeVoiceRecorder? rec}) async {
  final FakeConvexClient fake = FakeConvexClient();
  final FakeVoiceRecorder r = rec ?? FakeVoiceRecorder();
  final AppDeps d = await testDeps(fake, connected: connected, voice: r);
  await openChat(t, d);
  return (fake, r, d);
}

String _timer(WidgetTester t) => t.widget<Text>(find.byKey(_time)).data!;

Future<void> _record(WidgetTester t) async {
  await t.tap(find.byKey(_mic));
  await t.pump();
}

Future<void> _drain(WidgetTester t) async {
  for (int i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets('the mic shows only with an empty field and nothing attached', (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake,
        voice: FakeVoiceRecorder(), pickers: FakePickers(photo: UploadItem(path: 'p.png', name: 'p.png', bytes: tinyPng)));
    await openChat(t, d);
    expect(find.byKey(_mic), findsOneWidget);
    expect(find.byKey(_send), findsNothing);
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    expect(find.byKey(_mic), findsNothing);
    expect(find.byKey(_send), findsOneWidget);
    await t.enterText(find.byType(TextField), '');
    await t.pump();
    expect(find.byKey(_mic), findsOneWidget);
    // An attachment alone brings send back.
    await t.tap(find.byKey(const ValueKey<String>('composer-plus')));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(find.byKey(_mic), findsNothing);
    expect(find.byKey(_send), findsOneWidget);
  });

  testWidgets('mic and send sit in the same spot with the same size', (WidgetTester t) async {
    await _open(t);
    final Rect mic = t.getRect(find.byKey(_mic));
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    final Rect send = t.getRect(find.byKey(_send));
    expect(mic, send);
    expect(mic.size, const Size(44, 44));
  });

  testWidgets('tap starts the recording bar with a running timer', (WidgetTester t) async {
    final (FakeConvexClient _, FakeVoiceRecorder rec, AppDeps _) = await _open(t);
    await _record(t);
    expect(rec.calls, <String>['start']);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey<String>('record-dot')), findsOneWidget);
    expect(_timer(t), '0:00');
    await t.pump(const Duration(seconds: 7));
    expect(_timer(t), '0:07');
    await t.pump(const Duration(seconds: 60));
    expect(_timer(t), '1:07');
  });

  testWidgets('cancel discards the recording and sends nothing', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder rec, AppDeps _) = await _open(t);
    await _record(t);
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.byKey(_cancel));
    await t.pump();
    expect(rec.calls, <String>['start', 'cancel']);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(_mic), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    expect(fake.serverMessages, isEmpty);
    expect(fake.serverFiles, isEmpty);
    expect(fake.calls.where((String c) => c.startsWith('sendVoice')), isEmpty);
  });

  testWidgets('stop uploads and calls sendVoice with the file id; the bubble listens, then shows the text',
      (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder rec, AppDeps d) = await _open(t);
    await _record(t);
    await t.pump(const Duration(seconds: 4));
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(rec.calls, <String>['start', 'stop']);
    expect(fake.serverFiles.length, 1);
    final String fileId = fake.serverFiles.keys.single;
    final msg = fake.serverMessages[d.coach.currentId]!.single;
    expect(msg.fileIds, <String>[fileId]);
    expect(msg.voice, 'pending');
    expect(msg.text, '');
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('Thinking…'), findsNothing); // one waiting line, not two
    expect(find.byIcon(Icons.mic_none), findsWidgets);
    // The transcript arrives.
    fake.voiceDone(msg.id, 'I did three sets of squats');
    await _drain(t);
    expect(find.text('Listening…'), findsNothing);
    expect(find.text('I did three sets of squats'), findsOneWidget);
    expect(find.descendant(of: find.byType(ChatBubble), matching: find.byIcon(Icons.mic_none)), findsOneWidget);
  });

  testWidgets('the pending bubble shows at once while the upload runs', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps _) = await _open(t);
    fake.uploadGate = Completer<void>();
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(find.text('Listening…'), findsOneWidget);
    expect(fake.serverMessages, isEmpty);
    fake.uploadGate!.complete();
    await _drain(t);
    expect(fake.serverMessages.values.single.single.voice, 'pending');
  });

  testWidgets('a server failure shows "Try again", which calls retryVoice', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps d) = await _open(t);
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    final String id = fake.serverMessages[d.coach.currentId]!.single.id;
    fake.voiceFailed(id);
    await _drain(t);
    expect(find.text('Could not read the recording.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await _drain(t);
    expect(fake.calls, contains('retryVoice:$id'));
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('an old server without sendVoice leaves a failed bubble, never a crash', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps d) = await _open(t);
    fake.failVoice = const ConvexCallException('Could not find public function.');
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(t.takeException(), isNull);
    expect(find.text('Could not send the recording.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('That did not work.'), findsNothing); // the bubble says it, once
    // Try again goes through (the server now has the function): same message id.
    await t.tap(find.text('Try again'));
    await _drain(t);
    expect(fake.serverMessages[d.coach.currentId]!.single.voice, 'pending');
    expect(fake.serverFiles.length, 1); // the audio was not uploaded twice
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('permission denied shows one quiet line and no recording bar', (WidgetTester t) async {
    final (FakeConvexClient _, FakeVoiceRecorder _, AppDeps _) =
        await _open(t, rec: FakeVoiceRecorder(result: VoiceStart.denied));
    await _record(t);
    expect(find.text('Allow the microphone in Settings to record.'), findsOneWidget);
    expect(find.byKey(_time), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the mic is disabled offline', (WidgetTester t) async {
    final (FakeConvexClient _, FakeVoiceRecorder rec, AppDeps _) = await _open(t, connected: false);
    await t.tap(find.byKey(_mic));
    await t.pump();
    expect(rec.calls, isEmpty);
    expect(find.byKey(_time), findsNothing);
  });

  testWidgets('the recording stops by itself at 180 s and is sent', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder rec, AppDeps d) = await _open(t);
    await _record(t);
    await t.pump(const Duration(seconds: 179));
    expect(_timer(t), '2:59');
    expect(rec.calls, <String>['start']);
    await t.pump(const Duration(seconds: 1));
    await _drain(t);
    expect(rec.calls, <String>['start', 'stop']);
    expect(find.byType(TextField), findsOneWidget);
    expect(fake.serverMessages[d.coach.currentId]!.single.voice, 'pending');
  });
}
