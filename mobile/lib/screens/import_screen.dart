import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../data/api/open_gym_api.dart';
import '../models.dart';
import '../planner.dart';
import '../stores/import_store.dart';
import '../theme.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/cta_button.dart';
import '../widgets/import_job_card.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _pickError;

  ImportStore get _imports => widget.deps.imports;

  @override
  void initState() {
    super.initState();
    _imports.loadPast();
  }

  Future<void> _pickFiles() async {
    try {
      _imports.addAll(await widget.deps.pickers.pickFiles());
      _clearPickError();
    } catch (_) {
      _setPickError('Could not open the file picker.');
    }
  }

  Future<void> _pickPhoto() async {
    final String? src = await showChoiceSheet(
      context,
      title: 'Add a photo',
      choices: const <SheetChoice>[
        SheetChoice(value: 'camera', label: 'Take a photo'),
        SheetChoice(value: 'gallery', label: 'Choose from library'),
      ],
    );
    if (src == null) {
      return;
    }
    try {
      final UploadItem? p =
          await widget.deps.pickers.pickPhoto(camera: src == 'camera');
      if (p != null) {
        _imports.add(p);
      }
      _clearPickError();
    } catch (_) {
      _setPickError('Could not open the camera or library.');
    }
  }

  void _clearPickError() {
    if (mounted && _pickError != null) {
      setState(() => _pickError = null);
    }
  }

  void _setPickError(String m) {
    if (mounted) {
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
      listenable: _imports,
      builder: (BuildContext context, Widget? child) {
        final ImportStore s = _imports;
        final List<Widget> body = <Widget>[
          Text(
            'Add a file or a photo, like a screenshot of your history or the '
            'screen of a cycling machine.',
            style: OG.muted(),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OgButton(
                  onPressed: s.busy ? null : _pickFiles,
                  child: const Text('Files'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OgButton(
                  onPressed: s.busy ? null : _pickPhoto,
                  child: const Text('Photo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ];
        if (s.picked.isNotEmpty) {
          body.add(Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (int i = 0; i < s.picked.length; i++)
                AttachmentChip(name: s.picked[i].name, onRemove: () => s.removeAt(i)),
            ],
          ));
          body.add(const SizedBox(height: 12));
        }
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
        final List<ImportJob> older =
            s.past.where((ImportJob j) => j.id != job?.id).toList();
        if (older.isNotEmpty) {
          body.add(Text('Past imports', style: OG.display(24)));
          body.add(const SizedBox(height: 10));
          for (final ImportJob j in older) {
            body.add(_card(j, 'Import · ${whenLabel(j.createdAt).toLowerCase()}'));
            body.add(const SizedBox(height: 12));
          }
        }
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: CtaButton(
                    label: s.picked.isEmpty
                        ? 'Import'
                        : 'Import ${s.picked.length} item${s.picked.length == 1 ? '' : 's'}',
                    icon: Icons.file_upload_outlined,
                    variant: OgVariant.accent,
                    onPressed: (s.picked.isEmpty || s.busy) ? null : s.start,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
