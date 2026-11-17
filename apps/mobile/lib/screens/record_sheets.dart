import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_sheet.dart';

/// What the add-record sheet returns.
class RecordDraft {
  const RecordDraft({required this.title, required this.text, this.date});

  final String title;
  final String text;
  final String? date;
}

bool isIsoDate(String s) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) {
    return false;
  }
  final int y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final DateTime t = DateTime(y, mo, d);
  return t.year == y && t.month == mo && t.day == d;
}

/// Add a record: a title, an optional date and the pasted text. The text is
/// kept word for word.
Future<RecordDraft?> showRecordSheet(BuildContext context) {
  return showOgSheet<RecordDraft>(context, (BuildContext c) => const _RecordForm());
}

class _RecordForm extends StatefulWidget {
  const _RecordForm();

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _date = TextEditingController();
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _date.dispose();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final String title = _title.text.trim();
    final String date = _date.text.trim();
    final String text = _text.text;
    if (title.isEmpty || text.trim().isEmpty) {
      setState(() => _error = 'Give the record a title and paste its text.');
      return;
    }
    if (date.isNotEmpty && !isIsoDate(date)) {
      setState(() => _error = 'Write the date as 2026-10-12, or leave it empty.');
      return;
    }
    Navigator.of(context).pop(RecordDraft(
      title: title.length > 60 ? title.substring(0, 60) : title,
      date: date.isEmpty ? null : date,
      text: text.length > 8000 ? text.substring(0, 8000) : text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Add a record', style: OG.display(24)),
        const SizedBox(height: 14),
        LabeledField(label: 'Title', controller: _title, hint: 'Scan report'),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Date (optional)',
          controller: _date,
          hint: '2026-10-12',
          keyboardType: TextInputType.datetime,
        ),
        const SizedBox(height: 12),
        LabeledField(label: 'Text, pasted', controller: _text, maxLines: 8),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: OG.body(size: 14, weight: FontWeight.w600, color: const Color(0xFFE5482D))),
        ],
        const SizedBox(height: 14),
        OgButton(variant: OgVariant.accent, onPressed: _save, child: const Text('Save record')),
      ],
    );
  }
}

/// The full text of a record. Returns `remove` when the user removes it.
Future<String?> showRecordView(BuildContext context, LimitRecord r) {
  return showOgSheet<String>(context, (BuildContext c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(r.title, style: OG.display(24)),
        if (r.date != null) Text(r.date!, style: OG.muted(size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 12),
        SelectableText(r.text, style: OG.body(size: 15)),
        const SizedBox(height: 14),
        OgButton(
          onPressed: () => Navigator.of(c).pop('remove'),
          child: const Text('Remove record'),
        ),
      ],
    );
  });
}

/// A topic and a text for one preference note.
class NoteDraft {
  const NoteDraft({required this.topic, required this.text});

  final String topic;
  final String text;
}

Future<NoteDraft?> showNoteSheet(BuildContext context) {
  return showOgSheet<NoteDraft>(context, (BuildContext c) => const _NoteForm());
}

class _NoteForm extends StatefulWidget {
  const _NoteForm();

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  final TextEditingController _topic = TextEditingController(text: 'General');
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _topic.dispose();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final String text = _text.text.trim();
    if (text.isEmpty) {
      return;
    }
    final String topic = _topic.text.trim();
    Navigator.of(context).pop(NoteDraft(topic: topic.isEmpty ? 'General' : topic, text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Add a preference', style: OG.display(24)),
        const SizedBox(height: 14),
        LabeledField(label: 'Topic', controller: _topic, hint: 'Warm-up'),
        const SizedBox(height: 12),
        LabeledField(label: 'What the coach should know', controller: _text, maxLines: 3),
        const SizedBox(height: 14),
        OgButton(variant: OgVariant.accent, onPressed: _save, child: const Text('Add preference')),
      ],
    );
  }
}
