import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/entry_text.dart';
import 'package:opengym/models.dart';
import 'package:opengym/widgets/entry_list_item.dart';

import 'support/entry_fixtures.dart';

LogEntry _e({EntryRead? read, bool photo = true, String text = 'dinner'}) => LogEntry(
      id: 'e1',
      text: text,
      at: DateTime(2026, 11, 23, 20, 5).millisecondsSinceEpoch,
      createdAt: 1,
      files: photo ? <EntryFile>[imageFile('f1')] : const <EntryFile>[],
      read: read,
    );

void main() {
  test('the read label is parsed from the server item', () {
    final LogEntry e = LogEntry.fromJson(<String, dynamic>{
      'entryId': 'e1',
      'text': 'dinner',
      'at': 5,
      'createdAt': 5,
      'files': <Object?>[],
      'read': <String, dynamic>{'status': 'ready', 'kind': 'meal', 'summary': 'Pasta with tomato sauce.'},
    });
    expect(e.read!.ready, isTrue);
    expect(e.read!.kind, 'meal');
    expect(e.read!.summary, 'Pasta with tomato sauce.');
    expect(LogEntry.fromJson(<String, dynamic>{'entryId': 'e2', 'text': 'x', 'at': 5, 'createdAt': 5}).read, isNull);
  });

  test('a read note shows its kind after the time', () {
    final LogEntry e = _e(read: const EntryRead(status: 'ready', kind: 'meal', summary: 'Pasta.'));
    expect(entrySubtitle(e), endsWith('20:05 · Meal'));
    expect(entrySeenLine(e), 'Pasta.');
  });

  test('no kind for "other", for a failed read and for an old note', () {
    expect(entryKindLabel(_e(read: const EntryRead(status: 'ready', kind: 'other', summary: 'A receipt.'))), isNull);
    expect(entryKindLabel(_e(read: const EntryRead(status: 'failed'))), isNull);
    expect(entryKindLabel(_e()), isNull);
    expect(entrySeenLine(_e(read: const EntryRead(status: 'failed'))), isNull);
    expect(entrySeenLine(_e()), isNull);
  });

  test('a photo note says "Reading…" until it is read', () {
    expect(entrySeenLine(_e(read: const EntryRead(status: 'pending'))), 'Reading…');
  });

  test('a note with words only shows the kind and no extra line', () {
    final LogEntry e = _e(photo: false, text: 'slept badly', read: const EntryRead(status: 'ready', kind: 'body', summary: 'Poor sleep.'));
    expect(entrySubtitle(e), endsWith('· Body'));
    expect(entrySeenLine(e), isNull);
    expect(entrySeenLine(_e(photo: false, read: const EntryRead(status: 'pending'))), isNull);
  });

  testWidgets('the row shows the line about the photo', (WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: EntryListItem(title: 'dinner', subtitle: 'Today, 20:05 · Meal', detail: 'Pasta with tomato sauce.', attachments: 1)),
    ));
    expect(find.byKey(const ValueKey<String>('entry-detail')), findsOneWidget);
    expect(find.text('Pasta with tomato sauce.'), findsOneWidget);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: EntryListItem(title: 'dinner', subtitle: 'Today, 20:05'))));
    expect(find.byKey(const ValueKey<String>('entry-detail')), findsNothing);
  });
}
