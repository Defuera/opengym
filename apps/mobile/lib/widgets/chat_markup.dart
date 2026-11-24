import 'package:flutter/material.dart';

/// The small formatting the coach writes: `**bold**`, bullets ("• ", "- ",
/// "* ") and line breaks. Nothing else is parsed, and a raw asterisk never
/// shows: an unpaired one is dropped.
List<InlineSpan> chatInline(String line, TextStyle style) {
  final List<InlineSpan> spans = <InlineSpan>[];
  final List<String> parts = line.split('**');
  // An odd number of "**" leaves the last part unpaired: show it plain.
  final int pairs = (parts.length - 1) ~/ 2;
  for (int i = 0; i < parts.length; i++) {
    final bool bold = i.isOdd && i <= pairs * 2;
    final String t = parts[i].replaceAll('*', '');
    if (t.isEmpty) {
      continue;
    }
    spans.add(TextSpan(text: t, style: bold ? style.copyWith(fontWeight: FontWeight.w700) : style));
  }
  return spans;
}

final RegExp _bullet = RegExp(r'^\s*(?:[•\-]|\*(?!\*))\s+');
final RegExp _heading = RegExp(r'^\s*#{1,6}\s+');

/// Lays out [text] as lines: a bullet line gets a dot and a hanging indent, a
/// blank line a small gap. A text of one plain line is one [Text].
Widget chatMarkup(String text, TextStyle style) {
  final List<String> lines = text.trim().split('\n');
  if (lines.length == 1 && !_bullet.hasMatch(lines.first) && !_heading.hasMatch(lines.first)) {
    return Text.rich(TextSpan(children: chatInline(lines.first, style)), style: style);
  }
  final List<Widget> rows = <Widget>[];
  for (final String raw in lines) {
    if (raw.trim().isEmpty) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: 6));
      }
      continue;
    }
    final Match? b = _bullet.firstMatch(raw);
    if (b != null) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(padding: const EdgeInsets.only(left: 2, right: 8), child: Text('•', style: style)),
            Expanded(child: Text.rich(TextSpan(children: chatInline(raw.substring(b.end), style)), style: style)),
          ],
        ),
      ));
      continue;
    }
    final bool head = _heading.hasMatch(raw);
    final String body = head ? raw.replaceFirst(_heading, '') : raw;
    final TextStyle s = head ? style.copyWith(fontWeight: FontWeight.w700) : style;
    rows.add(Text.rich(TextSpan(children: chatInline(body, s)), style: s));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
}
