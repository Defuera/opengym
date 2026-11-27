import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/screens/comment_sheet.dart';
import 'package:opengym/widgets/composer_bar.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

/// ADR-043: the comment on an exercise is written in the same composer as the chat.
const ValueKey<String> _send = ValueKey<String>('composer-send');
const ValueKey<String> _mic = ValueKey<String>('composer-mic');

class _Host extends StatefulWidget {
  const _Host({required this.deps, this.text, this.fileIds = const <String>[]});

  final AppDeps deps;
  final String? text;
  final List<String> fileIds;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  CommentEdit? result;
  bool closed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const ValueKey<String>('open'),
          onPressed: () async {
            final CommentEdit? r = await showCommentSheet(context, widget.deps, text: widget.text, fileIds: widget.fileIds);
            setState(() {
              result = r;
              closed = r == null;
            });
          },
          child: Text(result == null ? 'open' : 'got:${result!.text}|${result!.fileIds.join(",")}|${result!.removedIds.join(",")}'),
        ),
      ),
    );
  }
}

Future<(FakeConvexClient, AppDeps)> _open(
  WidgetTester t, {
  String? text,
  List<String> fileIds = const <String>[],
  bool connected = true,
  FakePickers? pickers,
  FakeVoiceRecorder? voice,
  List<String> onServer = const <String>[],
}) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  for (final String id in onServer) {
    fake.serverFiles[id] = FileMeta(id: id, name: '$id.jpg', mime: 'image/jpeg', size: 1, kind: 'image', createdAt: 1);
  }
  final AppDeps d = await testDeps(fake, connected: connected, pickers: pickers, voice: voice ?? FakeVoiceRecorder());
  await t.pumpWidget(MaterialApp(home: _Host(deps: d, text: text, fileIds: fileIds)));
  await t.tap(find.byKey(const ValueKey<String>('open')));
  await t.pumpAndSettle();
  return (fake, d);
}

String _got(WidgetTester t) => t.widget<TextButton>(find.byKey(const ValueKey<String>('open'))).child is Text
    ? ((t.widget<TextButton>(find.byKey(const ValueKey<String>('open'))).child! as Text).data ?? '')
    : '';

void main() {
  testWidgets('the sheet is the shared composer, with the title and the question', (WidgetTester t) async {
    await _open(t);
    expect(find.text('Comment'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('comment-question')), findsOneWidget);
    expect(find.text('How did it go?'), findsOneWidget);
    expect(find.byType(ComposerBar), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-plus')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-camera')), findsOneWidget);
    expect(find.byKey(_mic), findsOneWidget);
  });

  testWidgets('text only: Save returns the text, with no upload and no wait', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _open(t);
    await t.enterText(find.byType(TextField), 'I feel my shoulder a bit');
    await t.pump();
    expect(find.bySemanticsLabel('Save'), findsOneWidget);
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(_got(t), 'got:I feel my shoulder a bit||');
    expect(fake.calls.where((String c) => c.startsWith('uploadFile')), isEmpty);
  });

  testWidgets('offline: text still saves at once; photos are switched off with a quiet line', (WidgetTester t) async {
    await _open(t, connected: false);
    expect(find.text(commentOfflineNote), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('composer-plus')));
    await t.pumpAndSettle();
    expect(find.text('Photo library'), findsNothing); // the "+" does nothing offline
    await t.enterText(find.byType(TextField), 'offline note');
    await t.pump();
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(_got(t), 'got:offline note||');
  });

  testWidgets('with photos: several from the library and the camera, uploaded on Save, then returned as ids', (WidgetTester t) async {
    final FakePickers pickers = FakePickers(photo: UploadItem(path: 'c.png', name: 'cam.png', bytes: tinyPng))
      ..photos = <UploadItem>[
        UploadItem(path: 'a.png', name: 'a.png', bytes: tinyPng),
        UploadItem(path: 'b.png', name: 'b.png', bytes: tinyPng),
      ];
    final (FakeConvexClient fake, AppDeps _) = await _open(t, pickers: pickers);
    await t.tap(find.byKey(const ValueKey<String>('composer-plus')));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('composer-camera')));
    await t.pumpAndSettle();
    expect(pickers.calls, <String>['library', 'camera']);
    await t.enterText(find.byType(TextField), 'level 9');
    await t.pump();
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(fake.calls.where((String c) => c.startsWith('uploadFile')), hasLength(3));
    final String got = _got(t);
    expect(got.startsWith('got:level 9|'), isTrue);
    expect(got.split('|')[1].split(','), hasLength(3));
  });

  testWidgets('removing a photo from an unsent draft asks nothing', (WidgetTester t) async {
    final FakePickers pickers = FakePickers(photo: UploadItem(path: 'c.png', name: 'cam.png', bytes: tinyPng));
    await _open(t, pickers: pickers);
    await t.tap(find.byKey(const ValueKey<String>('composer-camera')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('thumb-remove')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('thumb-remove')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('confirm-delete')), findsNothing);
    expect(find.byKey(const ValueKey<String>('thumb-remove')), findsNothing);
  });

  testWidgets('a failed upload keeps the sheet and everything typed, and says so', (WidgetTester t) async {
    final FakePickers pickers = FakePickers(photo: UploadItem(path: 'c.png', name: 'cam.png', bytes: tinyPng));
    final (FakeConvexClient fake, AppDeps _) = await _open(t, pickers: pickers);
    await t.tap(find.byKey(const ValueKey<String>('composer-camera')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'keep me');
    fake.failUpload = const ConvexCallException.unreachable();
    await t.pump();
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(find.text(commentUploadFailed), findsOneWidget);
    expect(find.widgetWithText(TextField, 'keep me'), findsOneWidget);
    // Try again goes through.
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(_got(t).startsWith('got:keep me|'), isTrue);
  });

  testWidgets('voice: the transcript lands in the field, nothing is saved until Save', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _open(t);
    await t.enterText(find.byType(TextField), '');
    await t.tap(find.byKey(_mic));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('composer-stop-record')));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'I did three sets of squats'), findsOneWidget);
    expect(fake.transcribedFiles, hasLength(1));
    expect(find.byType(ComposerBar), findsOneWidget); // still open: nothing saved yet
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(_got(t), 'got:I did three sets of squats||');
  });

  testWidgets('a saved comment shows its text; emptying it asks first, then returns empty', (WidgetTester t) async {
    await _open(t, text: 'Level 9, HR 140');
    expect(find.widgetWithText(TextField, 'Level 9, HR 140'), findsOneWidget);
    await t.enterText(find.byType(TextField), '');
    await t.pump();
    await t.tap(find.byKey(_send)); // send stays on for an empty save of a saved comment
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('confirm-delete')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    expect(_got(t), 'got:||');
  });

  testWidgets('keeping the saved comment on the question stays in the sheet', (WidgetTester t) async {
    await _open(t, text: 'Level 9');
    await t.enterText(find.byType(TextField), '');
    await t.pump();
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(find.byType(ComposerBar), findsOneWidget);
  });

  testWidgets('a saved photo asks before it goes, and is listed as removed', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _open(t, text: 'x', fileIds: <String>['p1'], onServer: <String>['p1']);
    expect(fake.serverFiles, isNotEmpty);
    expect(d.coach.localFile('p1'), isNull);
    await t.tap(find.byKey(const ValueKey<String>('thumb-remove')).first);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('confirm-delete')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(_got(t), 'got:x||p1');
  });
}
