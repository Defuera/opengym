/// Words for a note in lists and screens. Pure Dart.
library;

import 'package:flutter/painting.dart' show Color;

import 'entry_category.dart';
import 'models.dart';
import 'planner.dart';

/// Longest text a note holds.
const int entryMaxText = 2000;

/// Most files one note holds.
const int entryMaxFiles = 10;

String _two(int n) => n < 10 ? '0$n' : '$n';

/// "14:05".
String clockText(int ms) {
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

/// "12 Nov 2026".
String dateText(int ms) {
  const List<String> m = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// "Today, 14:05".
String entryWhen(int at, {int? nowMs}) => '${whenLabel(at, nowMs: nowMs)}, ${clockText(at)}';

/// "2 files" or "1 file".
String filesText(int n) => '$n file${n == 1 ? '' : 's'}';

/// First line of the text. With no text: "Photo" (all files are images,
/// one or more) or "N files".
String entryTitle(LogEntry e) {
  for (final String line in e.text.split('\n')) {
    if (line.trim().isNotEmpty) {
      return line.trim();
    }
  }
  if (e.files.length == 1 && e.files.first.isImage) {
    return 'Photo';
  }
  return e.files.isEmpty ? 'Note' : filesText(e.files.length);
}

/// "Meal", "Training", "Body", "Goal". Null while the note is not read, when
/// the read failed, and for a note that is none of these.
String? entryKindLabel(LogEntry e) {
  final EntryRead? r = e.read;
  if (r == null || !r.ready) {
    return null;
  }
  return categoryLabel(r.kind);
}

/// The colour of the note's category from the server, or null.
Color? entryCategoryColor(LogEntry e) => categoryLabel(e.read?.ready == true ? e.read?.kind : null) == null ? null : parseHexColor(e.read?.color);

/// The line under a note in a list: what the coach saw in its photos or
/// files, or "Reading…" while it reads them. Null for a note with words
/// only (the words say it) and when the read failed.
String? entrySeenLine(LogEntry e) {
  final EntryRead? r = e.read;
  if (r == null || e.files.isEmpty) {
    return null;
  }
  if (r.pending) {
    return 'Reading…';
  }
  final String s = (r.summary ?? '').trim();
  return r.ready && s.isNotEmpty ? s : null;
}

/// "Today, 14:05 · Meal".
String entrySubtitle(LogEntry e, {int? nowMs}) {
  final String? k = entryKindLabel(e);
  return k == null ? entryWhen(e.at, nowMs: nowMs) : '${entryWhen(e.at, nowMs: nowMs)} · $k';
}
