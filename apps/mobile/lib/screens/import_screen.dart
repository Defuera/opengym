import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../planner.dart';
import '../stores/import_store.dart';
import '../theme.dart';
import '../widgets/composer_bar.dart';
import '../widgets/import_job_card.dart';
import '../widgets/og_icon_button.dart';
import 'attach_flow.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _pickError;
  final TextEditingController _unused = TextEditingController();

  ImportStore get _imports => widget.deps.imports;

  @override
  void dispose() {
    _unused.dispose();
    super.dispose();
  }

  /// The "+" and the camera of the shared composer: the picks wait to be imported.
  Future<void> _attach() async {
    final String? error = await runAttachFlow(context, widget.deps.pickers, _imports.add);
    _setPickError(error);
  }

  Future<void> _camera() async {
    final String? error = await runCameraFlow(widget.deps.pickers, _imports.add);
    _setPickError(error);
  }

  void _setPickError(String? m) {
    if (mounted && _pickError != m) {
      setState(() => _pickError = m);
    }
  }

  String _summary(ImportJob j) {
    if (j.failed) {
      return 'This import failed.';
    }
    final ImportCounts c = j.counts;
    return '${c.sessions} sessions, ${c.goals} goals, ${c.context} context notes saved';
  }

  Widget _card(ImportJob j, String title) {
    return ImportJobCard(
      title: title,
      processed: j.processed,
      total: j.total,
      running: j.running,
      summary: _summary(j),
      notes: j.notes,
      onUndo: j.running ? null : () => _imports.undo(j.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_imports, widget.deps.connection]),
      builder: (BuildContext context, Widget? child) {
        final ImportStore s = _imports;
        final List<Widget> body = _uploadSection(s);
        final List<ImportJob> older = s.past.where((ImportJob j) => j.id != s.job?.id).toList();
        if (older.isNotEmpty) {
          body.add(Text('Past imports', style: OG.display(24)));
          body.add(const SizedBox(height: 10));
          for (final ImportJob j in older) {
            body.add(_card(j, 'Import · ${whenLabel(j.createdAt).toLowerCase()}'));
            body.add(const SizedBox(height: 12));
          }
        }
        return _page(s, body);
      },
    );
  }

  List<Widget> _uploadSection(ImportStore s) {
    final List<Widget> body = <Widget>[
      Text(
        'Add files or photos with the buttons below, like a screenshot of your history '
        'or the screen of a cycling machine. Then press send.',
        style: OG.muted(),
      ),
      const SizedBox(height: 14),
    ];
    final String err = s.error ?? _pickError ?? '';
    if (err.isNotEmpty) {
      body.add(Text(err, style: OG.body(size: 15, weight: FontWeight.w600)));
      body.add(const SizedBox(height: 12));
    }
    final ImportJob? job = s.job;
    if (s.uploading) {
      body.add(Text('Uploading…', style: OG.muted()));
      body.add(const SizedBox(height: 12));
    }
    if (job != null) {
      body.add(_card(job, 'This import'));
      body.add(const SizedBox(height: 14));
    }
    return body;
  }

  Widget _page(ImportStore s, List<Widget> body) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      OgIconButton(
                        icon: Icons.chevron_left,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Import', style: OG.display(32))),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...body,
                ],
              ),
            ),
            // The same composer as every chat. An import has no text, so the
            // field is off; the files wait in its strip and send starts the import.
            ComposerBar(
              controller: _unused,
              showText: false,
              sending: s.busy,
              offlineNote: widget.deps.connection.connected ? null : 'Offline. Import needs a connection.',
              attachments: stripItems(s.picked),
              onRemoveAttachment: s.busy ? null : s.removeAt,
              onAttach: _attach,
              onCamera: _camera,
              onSend: s.start,
            ),
          ],
        ),
      ),
    );
  }
}
