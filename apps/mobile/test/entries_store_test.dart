import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/convex_codec.dart';
import 'package:opengym/entry_text.dart';
import 'package:opengym/models.dart';
import 'package:opengym/stores/entries_store.dart';

import 'support/entry_fixtures.dart';
import 'support/fake_convex_client.dart';

void main() {
  late FakeConvexClient fake;
  late EntriesStore store;
  bool online = true;

  setUp(() async {
    fake = FakeConvexClient();
    online = true;
    store = EntriesStore(client: fake, isConnected: () => online)..start();
    await pump();
  });

  test('the live list comes newest first by time', () async {
    fake.serverEntries['a'] = (text: 'old', fileIds: <String>[], at: 100, createdAt: 1);
    fake.serverEntries['b'] = (text: 'new', fileIds: <String>[], at: 300, createdAt: 2);
    fake.serverChanged(() {});
    await pump();
    expect(store.entries.map((LogEntry e) => e.id), <String>['b', 'a']);
    expect(store.loading, isFalse);
  });

  test('save uploads the new files first, then saves with their ids', () async {
    final NewEntryFile f = NewEntryFile(upload('meal.jpg'));
    final bool ok = await store.save(
      entryId: 'e1',
      text: '  Lunch  ',
      at: 500,
      added: <NewEntryFile>[f],
    );
    await pump();
    expect(ok, isTrue);
    expect(fake.calls, <String>['uploadFile:${f.fileId}', 'saveEntry:e1']);
    final entry = fake.serverEntries['e1']!;
    expect(entry.text, 'Lunch');
    expect(entry.fileIds, <String>[f.fileId]);
    expect(entry.at, 500);
    expect(store.byId('e1')!.files.single.url, 'https://files.test/${f.fileId}');
    expect(store.busy, isFalse);
  });

  test('nothing to save is refused; a note with only a file is fine', () async {
    expect(await store.save(entryId: 'e1', text: '   ', at: 1), isFalse);
    expect(fake.calls, isEmpty);
    expect(
        await store.save(entryId: 'e1', text: '', at: 1, added: <NewEntryFile>[NewEntryFile(upload('a.jpg'))]),
        isTrue);
  });

  test('offline: says so and sends nothing', () async {
    online = false;
    expect(await store.save(entryId: 'e1', text: 'hi', at: 1), isFalse);
    expect(store.error, entriesOfflineMessage);
    expect(fake.calls, isEmpty);
    expect(await store.remove('e1'), isFalse);
  });

  test('a failed upload keeps the files; the retry uploads only what is missing', () async {
    final NewEntryFile a = NewEntryFile(upload('a.jpg'));
    final NewEntryFile b = NewEntryFile(upload('b.jpg'));
    fake.poison.add('uploadFile:${b.fileId}');
    expect(await store.save(entryId: 'e1', text: 'x', at: 1, added: <NewEntryFile>[a, b]), isFalse);
    expect(store.error, isNotNull);
    expect(a.uploaded, isTrue);
    expect(b.uploaded, isFalse);
    expect(fake.serverEntries, isEmpty);
    fake.poison.clear();
    fake.calls.clear();
    expect(await store.save(entryId: 'e1', text: 'x', at: 1, added: <NewEntryFile>[a, b]), isTrue);
    expect(fake.calls, <String>['uploadFile:${b.fileId}', 'saveEntry:e1']);
    expect(store.error, isNull);
  });

  test('a refused save shows the server words', () async {
    fake.failNext = const ConvexCallException('Too long.', kind: ConvexFailure.rejected);
    expect(await store.save(entryId: 'e1', text: 'x', at: 1), isFalse);
    expect(store.error, 'Too long.');
  });

  test('change a note: kept files stay, a dropped file goes', () async {
    final NewEntryFile a = NewEntryFile(upload('a.jpg'));
    final NewEntryFile b = NewEntryFile(upload('b.jpg'));
    await store.save(entryId: 'e1', text: 'x', at: 1, added: <NewEntryFile>[a, b]);
    await pump();
    expect(await store.save(entryId: 'e1', text: 'y', at: 1, createdAt: 7, keep: <String>[a.fileId]), isTrue);
    await pump();
    expect(store.byId('e1')!.files.map((EntryFile f) => f.id), <String>[a.fileId]);
    expect(fake.serverFiles.containsKey(b.fileId), isFalse);
    expect(store.byId('e1')!.createdAt, 7);
  });

  test('remove deletes the note and its files', () async {
    final NewEntryFile a = NewEntryFile(upload('a.jpg'));
    await store.save(entryId: 'e1', text: 'x', at: 1, added: <NewEntryFile>[a]);
    await pump();
    expect(await store.remove('e1'), isTrue);
    await pump();
    expect(store.entries, isEmpty);
    expect(fake.serverFiles, isEmpty);
  });

  test('model and text helpers', () {
    expect(entryTitle(note('a', '\n  First line \nsecond', 1)), 'First line');
    expect(entryTitle(note('a', '', 1, files: <EntryFile>[imageFile('f')])), 'Photo');
    expect(entryTitle(note('a', ' ', 1, files: <EntryFile>[imageFile('f'), docFile('g')])), '2 files');
    expect(entryTitle(note('a', '', 1, files: <EntryFile>[docFile('g')])), '1 file');
    final LogEntry e = decodeEntry(<String, Object?>{
      'entryId': 'x',
      'text': 't',
      'at': 5,
      'createdAt': 6,
      'files': <Object?>[
        <String, Object?>{
          'fileId': 'f',
          'name': 'a.png',
          'mime': 'image/png',
          'size': 1,
          'kind': 'image',
          'createdAt': 2,
          'url': null,
        },
      ],
    });
    expect(e.id, 'x');
    expect(e.files.single.id, 'f');
    expect(e.files.single.url, isNull);
    expect(e.files.single.isImage, isTrue);
  });
}
