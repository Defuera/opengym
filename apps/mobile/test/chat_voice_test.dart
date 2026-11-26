import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/transcript_result.dart';
import 'package:opengym/data/voice_recorder.dart';
import 'package:opengym/widgets/chat_bubble.dart';
import 'package:opengym/widgets/voice_wave.dart';

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

List<double> _levels(WidgetTester t) => t.widget<VoiceWave>(find.byType(VoiceWave)).levels;

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
  test('a dBFS level becomes 0..1: silence flat, speech tall', () {
    expect(levelFromDb(-160), 0);
    expect(levelFromDb(-50), 0);
    expect(levelFromDb(0), 1);
    expect(levelFromDb(-25), closeTo(0.5, 1e-9));
    expect(levelFromDb(double.nan), 0);
  });

  testWidgets('the mic shows alone with an empty field and nothing attached, and goes with typed text', (WidgetTester t) async {
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
    // An attachment alone brings send back, and the mic stays beside it.
    await t.tap(find.byKey(const ValueKey<String>('composer-plus')));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(find.byKey(_mic), findsOneWidget);
    expect(find.byKey(_send), findsOneWidget);
    expect(t.getRect(find.byKey(_mic)).right, lessThanOrEqualTo(t.getRect(find.byKey(_send)).left));
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

  testWidgets('the wave shows the levels the microphone hears, newest on the right', (WidgetTester t) async {
    final (FakeConvexClient _, FakeVoiceRecorder rec, AppDeps _) = await _open(t);
    await _record(t);
    expect(find.byKey(const ValueKey<String>('record-wave')), findsOneWidget);
    expect(find.byKey(_time), findsOneWidget);
    expect(find.byKey(_cancel), findsOneWidget);
    expect(find.byKey(_stop), findsOneWidget);
    expect(_levels(t), isEmpty);
    rec.hear(0.1);
    rec.hear(0.8);
    rec.hear(0.4);
    await t.pump();
    expect(_levels(t), <double>[0.1, 0.8, 0.4]);
    // The list is short: only the newest levels stay.
    for (int i = 0; i < 100; i++) {
      rec.hear(i / 100);
    }
    await t.pump();
    expect(_levels(t).length, 64);
    expect(_levels(t).last, 0.99);
  });

  testWidgets('stop uploads, shows Transcribing, and puts the text in the field; nothing is sent', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder rec, AppDeps d) = await _open(t);
    fake.transcribeGate = Completer<void>();
    await _record(t);
    await t.pump(const Duration(seconds: 4));
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(rec.calls, <String>['start', 'stop']);
    expect(find.text('Transcribing…'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(_mic), findsNothing);
    fake.transcribeGate!.complete();
    await _drain(t);
    expect(find.text('Transcribing…'), findsNothing);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'I did three sets of squats');
    // The audio went up, was read, and the server removed it. No message exists.
    expect(fake.transcribedFiles.length, 1);
    expect(fake.serverFiles, isEmpty);
    expect(fake.serverMessages[d.coach.currentId] ?? const <Object>[], isEmpty);
    expect(fake.sentContexts, isEmpty);
    // The person sends it as a typed message, with the screen context of a typed one.
    expect(find.byKey(_send), findsOneWidget);
    await t.tap(find.byKey(_send));
    await _drain(t);
    final msg = fake.serverMessages[d.coach.currentId]!.single;
    expect(msg.text, 'I did three sets of squats');
    expect(msg.voice, isNull);
    expect(fake.sentContexts.single?.screen, d.coach.chatContext?.screen ?? 'chat');
  });

  testWidgets('the text is added after the words already in the field', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps _) = await _open(t);
    fake.transcripts.addAll(<TranscriptResult>[
      const TranscriptResult.failed('No speech was heard.'),
      const TranscriptResult.text('my knee hurts'),
    ]);
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    // The person types while the note waits, then reads the recording again.
    await t.enterText(find.byType(TextField), 'Also,  ');
    await t.pump();
    await t.tap(find.text('Try again'));
    await _drain(t);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'Also, my knee hurts');
    expect(fake.sentContexts, isEmpty);
  });

  testWidgets('a failure keeps the recording; Try again reads the same upload', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps _) = await _open(t);
    fake.transcripts.addAll(<TranscriptResult>[
      const TranscriptResult.failed('The provider answered HTTP 401.'),
      const TranscriptResult.text('my knee hurts'),
    ]);
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(find.text('Could not read the recording. The provider answered HTTP 401.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(_mic), findsOneWidget);
    expect(fake.serverFiles.length, 1); // kept on the server for the retry
    await t.tap(find.text('Try again'));
    await _drain(t);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'my knee hurts');
    expect(find.text('Try again'), findsNothing);
    expect(fake.calls.where((String c) => c.startsWith('uploadFile')).length, 1); // not uploaded twice
    expect(fake.transcribedFiles.toSet().length, 1);
    expect(fake.serverFiles, isEmpty);
  });

  testWidgets('no connection while reading shows the note and a retry', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps _) = await _open(t);
    fake.failTranscribe = const ConvexCallException.unreachable();
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(find.textContaining('Could not read the recording.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Try again'));
    await _drain(t);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'I did three sets of squats');
  });

  testWidgets('close on the note drops the kept recording and its upload', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps _) = await _open(t);
    fake.transcripts.add(const TranscriptResult.failed('No speech was heard.'));
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(fake.serverFiles.length, 1);
    await t.tap(find.byKey(const ValueKey<String>('voice-discard')));
    await _drain(t);
    expect(find.text('Try again'), findsNothing);
    expect(find.byKey(const ValueKey<String>('voice-note')), findsNothing);
    expect(fake.serverFiles, isEmpty);
    expect(fake.sentContexts, isEmpty);
  });

  testWidgets('cancel while transcribing drops the recording; a late answer is not used', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps _) = await _open(t);
    fake.transcribeGate = Completer<void>();
    await _record(t);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    await t.tap(find.byKey(const ValueKey<String>('composer-cancel-transcribe')));
    await _drain(t);
    expect(find.text('Transcribing…'), findsNothing);
    fake.transcribeGate!.complete();
    await _drain(t);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(fake.sentContexts, isEmpty);
  });

  testWidgets('an old voice bubble still shows its states and Try again calls retryVoice', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder _, AppDeps d) = await _open(t);
    await d.coach.send('hi'); // makes the thread
    await _drain(t);
    await fake.sendVoice(threadId: d.coach.currentId!, messageId: 'old1', fileId: 'f-old');
    await _drain(t);
    expect(find.text('Listening…'), findsOneWidget);
    fake.voiceFailed('old1');
    await _drain(t);
    expect(find.text('Could not read the recording.'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await _drain(t);
    expect(fake.calls, contains('retryVoice:old1'));
    fake.voiceDone('old1', 'I did three sets of squats');
    await _drain(t);
    expect(find.text('I did three sets of squats'), findsOneWidget);
    expect(find.descendant(of: find.byType(ChatBubble), matching: find.byIcon(Icons.mic_none)), findsOneWidget);
  });

  testWidgets('permission denied shows one quiet line and no recording bar', (WidgetTester t) async {
    final (FakeConvexClient _, FakeVoiceRecorder _, AppDeps _) =
        await _open(t, rec: FakeVoiceRecorder(result: VoiceStart.denied));
    await _record(t);
    expect(find.text('Allow the microphone in Settings to record.'), findsOneWidget);
    expect(find.byKey(_time), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('offline the recording still works; reading it fails with a kept recording and Try again', (WidgetTester t) async {
    final (FakeConvexClient _, FakeVoiceRecorder rec, AppDeps _) = await _open(t, connected: false);
    await _record(t);
    expect(rec.calls, <String>['start']);
    expect(find.byKey(_time), findsOneWidget);
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(find.byKey(const ValueKey<String>('voice-note')), findsOneWidget);
    expect(find.textContaining('Offline. The recording is kept'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('voice-retry')), findsOneWidget);
  });

  testWidgets('the recording stops by itself at 180 s and its text goes to the field', (WidgetTester t) async {
    final (FakeConvexClient fake, FakeVoiceRecorder rec, AppDeps _) = await _open(t);
    await _record(t);
    await t.pump(const Duration(seconds: 179));
    expect(_timer(t), '2:59');
    expect(rec.calls, <String>['start']);
    await t.pump(const Duration(seconds: 1));
    await _drain(t);
    expect(rec.calls, <String>['start', 'stop']);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'I did three sets of squats');
    expect(fake.sentContexts, isEmpty);
  });
}
