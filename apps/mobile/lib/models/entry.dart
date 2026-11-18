import 'json_util.dart';

/// A file attached to a note, with the address that serves its bytes.
class EntryFile {
  const EntryFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
    required this.createdAt,
    this.url,
  });

  final String id;
  final String name;
  final String mime;
  final int size;

  /// text | image | pdf | audio | other
  final String kind;
  final int createdAt;

  /// Null when storage has lost the bytes.
  final String? url;

  bool get isImage => kind == 'image' || mime.startsWith('image/');

  factory EntryFile.fromJson(Map<String, dynamic> j) {
    return EntryFile(
      id: str(j['fileId']),
      name: str(j['name']),
      mime: str(j['mime']),
      size: intOf(j['size']),
      kind: str(j['kind'], 'other'),
      createdAt: intOf(j['createdAt']),
      url: strOrNull(j['url']),
    );
  }
}

/// A note: free text with a time, plus any number of photos or files.
class LogEntry {
  const LogEntry({
    required this.id,
    required this.text,
    required this.at,
    required this.createdAt,
    this.files = const <EntryFile>[],
  });

  final String id;
  final String text;

  /// The time the note is about (epoch ms). It orders the Home list.
  final int at;
  final int createdAt;
  final List<EntryFile> files;

  factory LogEntry.fromJson(Map<String, dynamic> j) {
    return LogEntry(
      id: str(j['entryId']),
      text: str(j['text']),
      at: intOf(j['at']),
      createdAt: intOf(j['createdAt']),
      files: <EntryFile>[
        for (final Object? f in asList(j['files'])) EntryFile.fromJson(asMap(f)),
      ],
    );
  }
}
