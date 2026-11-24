import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/entry_form_screen.dart';
import 'package:opengym/widgets/attachment_thumb.dart';
import 'package:opengym/widgets/composer_bar.dart';

import 'support/entry_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

/// The one button of the shared composer saves the note.
Finder _save() => find.byKey(const ValueKey<String>('composer-send'));

bool _enabled(WidgetTester t) => t.widget<GestureDetector>(_save()).onTap != null;

/// "+" opens the attach sheet; [label] is Photo library, Camera or File.
Future<void> _attach(WidgetTester t, String label) async {
  await t.tap(find.byKey(const ValueKey<String>('composer-plus')));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

/// The form that changes the existing entry n1 (a note with one photo).
Future<(FakeConvexClient, AppDeps, FakePickers)> _open(WidgetTester t, {bool connected = true}) async {
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps base = await testDeps(fake, connected: connected);
  final FakePickers pickers = FakePickers();
  final AppDeps d = AppDeps(
    client: base.client, store: base.store, connection: base.connection, outbox: base.outbox,
    plans: base.plans, dashboard: base.dashboard, goals: base.goals, entries: base.entries,
    context: base.context, coach: base.coach, imports: base.imports, reviews: base.reviews,
    pickers: pickers, voice: base.voice, about: base.about, aiModel: base.aiModel,
    tracker: base.tracker, places: base.places, art: base.art, programs: base.programs,
  );
  fake.serverFiles['p'] = const FileMeta(id: 'p', name: 'meal.jpg', mime: 'image/jpeg', size: 1, kind: 'image', createdAt: 1);
  fake.serverEntries['n1'] = (text: 'Oats', fileIds: <String>['p'], at: entryNow, createdAt: entryNow);
  d.entries.start();
  fake.serverChanged(() {});
  await t.pumpWidget(MaterialApp(home: EntryFormScreen(deps: d, entry: d.entries.byId('n1') ?? LogEntry(id: 'n1', text: 'Oats', at: entryNow, createdAt: entryNow, files: <EntryFile>[imageFile('p')]))));
  await t.pumpAndSettle();
  return (fake, d, pickers);
}

void main() {
  testWidgets('it edits an existing entry: text and time are kept, nothing opens on its own', (WidgetTester t) async {
    final (FakeConvexClient fake, _, FakePickers p) = await _open(t);
    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text('Oats'), findsOneWidget);
    expect(find.byType(AttachmentThumb), findsOneWidget);
    expect(find.byType(ComposerBar), findsOneWidget); // the same composer as every chat
    expect(find.byKey(const ValueKey<String>('composer-camera')), findsOneWidget);
    expect(p.lastCamera, isNull);
    expect(fake.calls, isEmpty);
  });

  testWidgets('Save is off with no text and no file, on again with text', (WidgetTester t) async {
    await _open(t);
    await t.tap(find.byKey(const ValueKey<String>('thumb-remove')));
    await t.pump();
    expect(find.byType(AttachmentThumb), findsNothing);
    await t.enterText(find.byType(TextField), '   ');
    await t.pump();
    expect(_enabled(t), isFalse);
    await t.enterText(find.byType(TextField), 'Oats and eggs');
    await t.pump();
    expect(_enabled(t), isTrue);
  });

  testWidgets('a new file uploads first, then the entry is saved with the same id', (WidgetTester t) async {
    final (FakeConvexClient fake, _, FakePickers p) = await _open(t);
    p.files = <UploadItem>[upload('plan.pdf')];
    await _attach(t, 'File');
    await t.tap(_save());
    await t.pumpAndSettle();
    expect(fake.calls[0], startsWith('uploadFile:'));
    expect(fake.calls[1], startsWith('saveEntry:n1'));
    expect(fake.serverEntries['n1']!.fileIds, hasLength(2));
    expect(fake.serverEntries, hasLength(1));
  });

  testWidgets('a failure keeps the text and files and shows a plain error; retry works', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d, FakePickers p) = await _open(t);
    await t.enterText(find.byType(TextField), 'Dinner');
    p.photo = upload('d.jpg');
    await _attach(t, 'Photo library');
    fake.failUpload = const ConvexCallException.unreachable();
    await t.tap(_save());
    await t.pumpAndSettle();
    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.byType(AttachmentThumb), findsNWidgets(2));
    await t.tap(_save());
    await t.pumpAndSettle();
    expect(fake.serverEntries['n1']!.text, 'Dinner');
    expect(d.entries.error, isNull);
  });

  testWidgets('progress shows while the upload runs', (WidgetTester t) async {
    final (FakeConvexClient fake, _, FakePickers p) = await _open(t);
    p.photo = upload('d.jpg');
    await _attach(t, 'Photo library');
    fake.uploadGate = Completer<void>();
    await t.tap(_save());
    await t.pump();
    expect(find.text('Uploading 1 of 1…'), findsOneWidget);
    expect(_enabled(t), isFalse);
    fake.uploadGate!.complete();
    await t.pumpAndSettle();
  });

  testWidgets('offline: the composer says so and is off', (WidgetTester t) async {
    await _open(t, connected: false);
    expect(find.text(entryOfflineNote), findsOneWidget);
    expect(_enabled(t), isFalse);
  });

  testWidgets('a picker that fails shows the chat wording', (WidgetTester t) async {
    final (_, _, FakePickers p) = await _open(t);
    p.fail = true;
    await t.tap(find.byKey(const ValueKey<String>('composer-camera')));
    await t.pumpAndSettle();
    expect(find.text('Could not open the camera or library.'), findsOneWidget);
  });
}
