import 'package:flutter/material.dart';

import '../widgets/attachment_strip.dart';
import '../widgets/chip_strip.dart';
import '../widgets/composer_bar.dart';
import '../widgets/labeled_field.dart';

class FieldDemo extends StatefulWidget {
  const FieldDemo({super.key});

  @override
  State<FieldDemo> createState() => _FieldDemoState();
}

class _FieldDemoState extends State<FieldDemo> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController(text: 'secret');

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        LabeledField(label: 'Server URL', controller: _a, hint: 'http://…'),
        const SizedBox(height: 12),
        LabeledField(label: 'Token', controller: _b, obscure: true),
      ],
    );
  }
}

class ComposerDemo extends StatefulWidget {
  const ComposerDemo({super.key});

  @override
  State<ComposerDemo> createState() => _ComposerDemoState();
}

class _ComposerDemoState extends State<ComposerDemo> {
  final TextEditingController _c = TextEditingController();
  final List<String> _files = <String>['notes.txt'];
  bool _sending = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ComposerBar(
      controller: _c,
      sending: _sending,
      attachments: <StripItem>[for (final String f in _files) StripItem(name: f)],
      onRemoveAttachment: (int i) => setState(() => _files.removeAt(i)),
      onAttach: () => setState(() => _files.add('file ${_files.length + 1}.txt')),
      onSend: () => setState(() => _sending = !_sending),
    );
  }
}

class ChipStripDemo extends StatefulWidget {
  const ChipStripDemo({super.key});

  @override
  State<ChipStripDemo> createState() => _ChipStripDemoState();
}

class _ChipStripDemoState extends State<ChipStripDemo> {
  final List<String> _names = <String>['General', 'Squat', 'Plan'];
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    return ChipStrip(
      labels: _names,
      selectedIndex: _sel,
      onSelect: (int i) => setState(() => _sel = i),
      onAdd: () => setState(() => _names.add('Thread ${_names.length + 1}')),
    );
  }
}
