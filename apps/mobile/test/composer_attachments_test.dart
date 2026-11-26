import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/stores/coach_store.dart';
import 'package:opengym/widgets/attach_sheet.dart';
import 'package:opengym/widgets/attachment_thumb.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const ValueKey<String> _mic = ValueKey<String>('composer-mic');
const ValueKey<String> _send = ValueKey<String>('composer-send');
const ValueKey<String> _plus = ValueKey<String>('composer-plus');
const ValueKey<String> _camera = ValueKey<String>('composer-camera');
const ValueKey<String> _stop = ValueKey<String>('composer-stop-record');

UploadItem _p(int i) => UploadItem(path: 'p$i.png', name: 'p$i.png', bytes: tinyPng);

Future<(FakeConvexClient, FakePickers, AppDeps)> _open(WidgetTester t, {List<UploadItem>? photos, Size size = const Size(390, 844)}) async {
  final FakeConvexClient fake = FakeConvexClient();
  final FakePickers p = FakePickers(photo: _p(0))..photos = photos;
  final AppDeps d = await testDeps(fake, pickers: p, voice: FakeVoiceRecorder());
  await openChat(t, d, size: size);
  return (fake, p, d);
}

Future<void> _library(WidgetTester t) async {
  await t.tap(find.byKey(_plus));
  await t.pumpAndSettle();
  await t.tap(find.text('Photo library'));
  await t.pumpAndSettle();
}

Future<void> _drain(WidgetTester t) async {
  for (int i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets('with attachments and an empty field the mic and send both show, mic left of send', (WidgetTester t) async {
    await _open(t, photos: <UploadItem>[_p(1), _p(2), _p(3)], size: const Size(360, 780));
    await _library(t);
    expect(find.byType(AttachmentThumb), findsNWidgets(3));
    expect(find.byKey(_mic), findsOneWidget);
    expect(find.byKey(_send), findsOneWidget);
    expect(t.getRect(find.byKey(_mic)).right, lessThanOrEqualTo(t.getRect(find.byKey(_send)).left));
    expect(t.takeException(), isNull); // fits 360 px wide
    // Typing a text takes the mic away; send stays.
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    expect(find.byKey(_mic), findsNothing);
    expect(find.byKey(_send), findsOneWidget);
  });

  testWidgets('a recording keeps the thumbnails, the transcript lands in the field, the attachments stay and go out with the text', (WidgetTester t) async {
    final (FakeConvexClient fake, FakePickers _, AppDeps d) = await _open(t, photos: <UploadItem>[_p(1), _p(2)]);
    await _library(t);
    fake.transcribeGate = Completer<void>();
    await t.tap(find.byKey(_mic));
    await t.pump();
    expect(find.byType(AttachmentThumb), findsNWidgets(2)); // still visible while recording
    expect(find.byKey(const ValueKey<String>('thumb-remove')), findsNothing); // but not removable
    await t.pump(const Duration(seconds: 2));
    await t.tap(find.byKey(_stop));
    await _drain(t);
    expect(find.text('Transcribing…'), findsOneWidget);
    expect(find.byType(AttachmentThumb), findsNWidgets(2));
    fake.transcribeGate!.complete();
    await _drain(t);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isNotEmpty);
    expect(find.byType(AttachmentThumb), findsNWidgets(2));
    expect(find.byKey(const ValueKey<String>('thumb-remove')), findsNWidgets(2));
    expect(d.coach.attachments.length, 2);
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(d.coach.attachments, isEmpty);
    expect(fake.serverFiles.length, 2);
  });

  testWidgets('the library picks several photos at once, and the plus and the camera still work after', (WidgetTester t) async {
    final (FakeConvexClient _, FakePickers p, AppDeps d) = await _open(t, photos: <UploadItem>[_p(1), _p(2), _p(3)]);
    await _library(t);
    expect(d.coach.attachments.length, 3);
    await _library(t); // a second add through the plus
    expect(d.coach.attachments.length, 6);
    await t.tap(find.byKey(_camera));
    await t.pumpAndSettle();
    await t.tap(find.byKey(_camera)); // the camera button again
    await t.pumpAndSettle();
    expect(d.coach.attachments.length, 8);
    expect(p.calls, <String>['library', 'library', 'camera', 'camera']);
  });

  testWidgets('a pick over the limit of the server is dropped and a quiet line says so', (WidgetTester t) async {
    final (FakeConvexClient _, FakePickers _, AppDeps d) = await _open(t, photos: <UploadItem>[for (int i = 0; i < 12; i++) _p(i)]);
    await _library(t);
    expect(d.coach.attachments.length, messageMaxFiles);
    expect(find.text('A message holds up to $messageMaxFiles files.'), findsOneWidget);
    expect(messageMaxFiles, 10);
  });

  testWidgets('the plus sheet of the chat has two rows, the camera has its own button', (WidgetTester t) async {
    await _open(t);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);
  });

  testWidgets('a composer without a camera button keeps the camera row (the parameter)', (WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
      ctx = c;
      return const SizedBox();
    })));
    unawaited(showAttachSheet(ctx));
    await t.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    unawaited(showAttachSheet(ctx, includeCamera: false));
    await t.pumpAndSettle();
    expect(find.text('Camera'), findsNothing);
  });
}
