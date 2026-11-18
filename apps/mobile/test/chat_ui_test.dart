import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/pickers.dart';
import 'package:opengym/widgets/attachment_thumb.dart';
import 'package:opengym/widgets/chat_bubble.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const ValueKey<String> _plus = ValueKey<String>('composer-plus');
const ValueKey<String> _send = ValueKey<String>('composer-send');

UploadItem _photo() => UploadItem(path: 'p.png', name: 'p.png', bytes: tinyPng);

bool _sendOn(WidgetTester t) => t.widget<GestureDetector>(find.byKey(_send)).onTap != null;

EditableText _field(WidgetTester t) => t.widget<EditableText>(find.byType(EditableText));

void main() {
  testWidgets('empty chat: one quiet hint, no thread chips, send is off', (WidgetTester t) async {
    final AppDeps d = await testDeps(FakeConvexClient());
    await openChat(t, d);
    expect(find.byKey(const ValueKey<String>('chat-hint')), findsOneWidget);
    expect(find.text('+ New'), findsNothing);
    expect(_sendOn(t), isFalse);
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    expect(_sendOn(t), isTrue);
    await t.enterText(find.byType(TextField), '   ');
    await t.pump();
    expect(_sendOn(t), isFalse);
  });

  testWidgets('the plus sheet offers Photo library, Camera and File, and closes', (WidgetTester t) async {
    final FakePickers p = FakePickers(photo: _photo());
    final AppDeps d = await testDeps(FakeConvexClient(), pickers: p);
    await openChat(t, d);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(find.text('Camera'), findsNothing);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    await t.tap(find.text('Camera'));
    await t.pumpAndSettle();
    expect(p.calls, <String>['camera']);
  });

  testWidgets('a photo shows as a thumbnail, enables send, and can be removed', (WidgetTester t) async {
    final AppDeps d = await testDeps(FakeConvexClient(), pickers: FakePickers(photo: _photo()));
    await openChat(t, d);
    expect(find.byType(AttachmentThumb), findsNothing);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(find.byType(AttachmentThumb), findsOneWidget);
    expect(find.text('p.png'), findsNothing); // a picture, not a file name
    expect(_sendOn(t), isTrue); // an attachment alone is enough
    await t.tap(find.byKey(const ValueKey<String>('thumb-remove')));
    await t.pumpAndSettle();
    expect(find.byType(AttachmentThumb), findsNothing);
    expect(_sendOn(t), isFalse);
  });

  testWidgets('a file shows as a chip with its name', (WidgetTester t) async {
    final AppDeps d = await testDeps(FakeConvexClient(),
        pickers: FakePickers(files: <UploadItem>[const UploadItem(path: 'h.csv', name: 'history.csv', bytes: <int>[1])]));
    await openChat(t, d);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    await t.tap(find.text('File'));
    await t.pumpAndSettle();
    expect(find.text('history.csv'), findsOneWidget);
    expect(find.byType(AttachmentThumb), findsNothing);
  });

  testWidgets('a sent photo shows as a thumbnail in the bubble', (WidgetTester t) async {
    final AppDeps d = await testDeps(FakeConvexClient(), pickers: FakePickers(photo: _photo()));
    await openChat(t, d);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'my elbow');
    await t.pump();
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(ChatBubble), matching: find.byType(AttachmentThumb)), findsOneWidget);
    expect(find.textContaining('Attached:'), findsNothing);
  });

  testWidgets('chats button opens the list; picking a chat switches to it', (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    await fake.createThread(threadId: 'a', title: 'Squat progress');
    await fake.createThread(threadId: 'b', title: 'Left arm pain');
    final AppDeps d = await testDeps(fake);
    await openChat(t, d);
    expect(find.text('Squat progress'), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('chat-threads')));
    await t.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Squat progress'), findsOneWidget);
    await t.tap(find.text('Squat progress'));
    await t.pumpAndSettle();
    expect(d.coach.currentId, 'a');
    expect(find.text('Chats'), findsNothing);
    expect(find.text('Squat progress'), findsOneWidget); // now the title
    // New chat from the same sheet.
    await t.tap(find.byKey(const ValueKey<String>('chat-threads')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('chats-new')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(d.coach.isDraft, isTrue);
    expect(find.text('New chat'), findsOneWidget);
  });

  testWidgets('a long title stays on one line and no overflow at 390 pt', (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    await fake.createThread(
        threadId: 'a', title: 'A very long chat title about my left shoulder and the way it hurts when I press');
    final AppDeps d = await testDeps(fake);
    await openChat(t, d);
    await d.coach.openThread('a');
    await t.pumpAndSettle();
    final Finder title = find.descendant(of: find.byKey(const ValueKey<String>('chat-title')), matching: find.byType(Text));
    expect(t.getSize(title).height, lessThan(40));
    expect(t.widget<Text>(title).maxLines, 1);
    expect(t.takeException(), isNull);
  });

  group('keyboard', () {
    testWidgets('a tap on the messages or the header closes it; a drag closes it', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      await openChat(t, d);
      await t.enterText(find.byType(TextField), 'hello');
      await t.pump();
      await t.tap(find.byKey(_send));
      await t.pumpAndSettle();

      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      expect(_field(t).focusNode.hasFocus, isTrue);
      await t.tapAt(const Offset(200, 300)); // message area
      await t.pumpAndSettle();
      expect(_field(t).focusNode.hasFocus, isFalse);

      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(250, 30)); // empty part of the header
      await t.pumpAndSettle();
      expect(_field(t).focusNode.hasFocus, isFalse);

      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      expect(_field(t).focusNode.hasFocus, isTrue);
      for (int i = 0; i < 12; i++) {
        fake.coachAnswers(d.coach.currentId!, 'Answer number $i from the coach, long enough to fill space.');
      }
      await t.pumpAndSettle();
      await t.drag(find.byKey(const ValueKey<String>('chat-messages')), const Offset(0, 120));
      await t.pumpAndSettle();
      expect(_field(t).focusNode.hasFocus, isFalse);
    });

    testWidgets('the empty hint area closes it too; sending keeps it open', (WidgetTester t) async {
      final AppDeps d = await testDeps(FakeConvexClient());
      await openChat(t, d);
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('chat-hint')));
      await t.pumpAndSettle();
      expect(_field(t).focusNode.hasFocus, isFalse);

      await t.tap(find.byType(TextField));
      await t.enterText(find.byType(TextField), 'hi');
      await t.pump();
      await t.tap(find.byKey(_send));
      await t.pumpAndSettle();
      expect(_field(t).focusNode.hasFocus, isTrue);
    });
  });

  testWidgets('the newest message stays in view when the keyboard opens and when one arrives',
      (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    await openChat(t, d);
    await t.enterText(find.byType(TextField), 'start');
    await t.pump();
    await t.tap(find.byKey(_send));
    await t.pumpAndSettle();
    for (int i = 0; i < 12; i++) {
      fake.coachAnswers(d.coach.currentId!, 'Answer number $i from the coach, long enough to fill space.');
    }
    await t.pumpAndSettle();
    final Finder newest = find.textContaining('Answer number 11');
    final double composerTop = t.getTopLeft(find.byKey(_plus)).dy;
    expect(t.getRect(newest).bottom, lessThanOrEqualTo(composerTop));
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(t.getRect(newest).bottom, lessThanOrEqualTo(t.getTopLeft(find.byKey(_plus)).dy));
    expect(t.getRect(newest).top, greaterThan(0));
    fake.coachAnswers(d.coach.currentId!, 'One more arrives');
    await t.pumpAndSettle();
    expect(t.getRect(find.text('One more arrives')).bottom, lessThanOrEqualTo(t.getTopLeft(find.byKey(_plus)).dy));
  });

  testWidgets('the composer rises with the keyboard without overflow', (WidgetTester t) async {
    final AppDeps d = await testDeps(FakeConvexClient(), pickers: FakePickers(photo: _photo()));
    await openChat(t, d);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'line one\nline two\nline three\nline four\nline five\nline six');
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(t.getRect(find.byType(TextField)).bottom, lessThan(844 - 336));
  });
}
