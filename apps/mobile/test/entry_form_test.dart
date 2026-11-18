import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/screens/entry_form_screen.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/widgets/og_button.dart';

import 'support/entry_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';
import 'support/test_deps.dart';

Finder _save() => find.widgetWithText(OgButton, 'Save');

bool _enabled(WidgetTester t, Finder f) => t.widget<OgButton>(f).onPressed != null;

Future<(FakeConvexClient, AppDeps, FakePickers)> _openForm(WidgetTester t,
    {bool connected = true}) async {
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps base = await testDeps(fake, connected: connected);
  final FakePickers pickers = FakePickers();
  final AppDeps d = AppDeps(
    client: base.client,
    store: base.store,
    connection: base.connection,
    outbox: base.outbox,
    plans: base.plans,
    dashboard: base.dashboard,
    goals: base.goals,
    entries: base.entries,
    context: base.context,
    coach: base.coach,
    imports: base.imports,
    reviews: base.reviews,
    pickers: pickers,
    about: base.about,
    aiModel: base.aiModel,
    tracker: base.tracker,
    places: base.places,
  );
  await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
  await t.pump();
  await openLog(t);
  await t.tap(inSheet(find.text('Note')));
  await t.pumpAndSettle();
  return (fake, d, pickers);
}

void main() {
  testWidgets('Plus, Log: "Note" is the first choice and opens the form (the sheet closes)',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d, FakePickers p) = await _openForm(t);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('New note'), findsOneWidget);
    expect(fake.calls, isEmpty);
    expect(d.entries.entries, isEmpty);
    expect(p.files, isEmpty);
  });

  testWidgets('the Log tab shows Note above the activities, with its line', (WidgetTester t) async {
    await openHome(t);
    await openLog(t);
    expect(inSheet(find.text('A meal, a photo, anything.')), findsOneWidget);
    expect(t.getTopLeft(inSheet(find.text('Note'))).dy,
        lessThan(t.getTopLeft(inSheet(find.text('Cycling'))).dy));
  });

  testWidgets('Save is off with no text and no file, on with text', (WidgetTester t) async {
    await _openForm(t);
    expect(_enabled(t, _save()), isFalse);
    await t.enterText(find.byType(TextField), '   ');
    await t.pump();
    expect(_enabled(t, _save()), isFalse);
    await t.enterText(find.byType(TextField), 'Oats and eggs');
    await t.pump();
    expect(_enabled(t, _save()), isTrue);
  });

  testWidgets('a photo alone turns Save on; remove turns it off again', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d, FakePickers p) = await _openForm(t);
    p.photo = upload('lunch.jpg');
    await t.tap(find.byKey(const ValueKey<String>('entry-attach')));
    await t.pumpAndSettle();
    await t.tap(find.text('Take a photo'));
    await t.pumpAndSettle();
    expect(p.lastCamera, isTrue);
    expect(find.text('lunch.jpg'), findsOneWidget);
    expect(_enabled(t, _save()), isTrue);
    await t.tap(find.byIcon(Icons.close));
    await t.pump();
    expect(find.text('lunch.jpg'), findsNothing);
    expect(_enabled(t, _save()), isFalse);
    expect(fake.calls, isEmpty);
    expect(d.entries.busy, isFalse);
  });

  testWidgets('save sends the files first, then the note; the form closes', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d, FakePickers p) = await _openForm(t);
    await t.enterText(find.byType(TextField), 'Oats\nand eggs');
    p.files = <UploadItem>[upload('plan.pdf'), upload('menu.txt')];
    await t.tap(find.byKey(const ValueKey<String>('entry-attach')));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose a file'));
    await t.pumpAndSettle();
    expect(find.text('plan.pdf'), findsOneWidget);
    expect(find.text('menu.txt'), findsOneWidget);
    final int before = DateTime.now().millisecondsSinceEpoch;
    await t.tap(_save());
    await t.pumpAndSettle();
    expect(fake.calls.length, 3);
    expect(fake.calls[0], startsWith('uploadFile:'));
    expect(fake.calls[1], startsWith('uploadFile:'));
    expect(fake.calls[2], startsWith('saveEntry:'));
    final e = fake.serverEntries.values.single;
    expect(e.text, 'Oats\nand eggs');
    expect(e.fileIds, hasLength(2));
    expect(e.at, greaterThanOrEqualTo(before - 60000));
    expect(e.at, lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch + 60000));
    expect(find.text('New note'), findsNothing);
    expect(d.entries.entries.single.text, 'Oats\nand eggs');
  });

  testWidgets('a failure keeps the text and the files, shows a plain error, and retry works',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d, FakePickers p) = await _openForm(t);
    await t.enterText(find.byType(TextField), 'Dinner');
    p.photo = upload('d.jpg');
    await t.tap(find.byKey(const ValueKey<String>('entry-attach')));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose from library'));
    await t.pumpAndSettle();
    fake.failUpload = const ConvexCallException.unreachable();
    await t.tap(_save());
    await t.pumpAndSettle();
    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('d.jpg'), findsOneWidget);
    expect(fake.serverEntries, isEmpty);
    await t.tap(find.widgetWithText(OgButton, 'Try again'));
    await t.pumpAndSettle();
    expect(fake.serverEntries.values.single.text, 'Dinner');
    expect(d.entries.error, isNull);
  });

  testWidgets('progress shows while the upload runs', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d, FakePickers p) = await _openForm(t);
    await t.enterText(find.byType(TextField), 'x');
    p.photo = upload('d.jpg');
    await t.tap(find.byKey(const ValueKey<String>('entry-attach')));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose from library'));
    await t.pumpAndSettle();
    fake.uploadGate = Completer<void>();
    await t.tap(_save());
    await t.pump();
    expect(find.byKey(const ValueKey<String>('entry-progress')), findsOneWidget);
    expect(find.text('Uploading 1 of 1…'), findsOneWidget);
    expect(_enabled(t, _save()), isFalse);
    fake.uploadGate!.complete();
    await t.pumpAndSettle();
    expect(fake.serverEntries.values.single.text, 'x');
    expect(d.entries.busy, isFalse);
  });

  testWidgets('offline: says so and Save is off', (WidgetTester t) async {
    await _openForm(t, connected: false);
    await t.enterText(find.byType(TextField), 'Lunch');
    await t.pump();
    expect(find.text(entryOfflineNote), findsOneWidget);
    expect(_enabled(t, _save()), isFalse);
  });

  testWidgets('a picker that fails shows the chat wording', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps _, FakePickers p) = await _openForm(t);
    p.fail = true;
    await t.tap(find.byKey(const ValueKey<String>('entry-attach')));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose a file'));
    await t.pumpAndSettle();
    expect(find.text('Could not open the file picker.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('entry-attach')));
    await t.pumpAndSettle();
    await t.tap(find.text('Take a photo'));
    await t.pumpAndSettle();
    expect(find.text('Could not open the camera or library.'), findsOneWidget);
  });
}
