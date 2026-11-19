import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/about_store.dart';
import '../stores/context_store.dart';
import '../theme.dart';
import '../widgets/body_figure.dart';
import '../widgets/footnote.dart';
import '../widgets/limit_card.dart';
import '../widgets/note_box.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/new_kind_row.dart';
import '../widgets/part_card.dart';
import '../widgets/program_row.dart';
import '../widgets/section_header.dart';
import '../widgets/segmented_toggle.dart';
import 'about_preferences.dart';
import 'limit_detail_screen.dart';
import 'limit_sheets.dart';
import 'program_new_screen.dart';
import 'program_screen.dart';
import 'program_text.dart';

/// "About me": what the coach knows. The body figure, the limits and the
/// preferences (coach notes).
class AboutMeScreen extends StatefulWidget {
  const AboutMeScreen({
    super.key,
    required this.about,
    required this.notes,
    this.exercises = const <String>[],
    this.deps,
  });

  /// With the app deps the screen lists the programs and starts a new one.
  final AppDeps? deps;

  final AboutStore about;
  final ContextStore notes;

  /// Known exercise names, for the rule sheet.
  final List<String> exercises;

  @override
  State<AboutMeScreen> createState() => _AboutMeScreenState();
}

class _AboutMeScreenState extends State<AboutMeScreen> {
  int _days = 14;
  String? _selected;

  AboutStore get _about => widget.about;

  void _openLimit(Limit l) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext c) =>
          LimitDetailScreen(about: _about, limitId: l.id, exercises: widget.exercises),
    ));
  }

  Future<void> _addLimit({String? part}) async {
    final LimitDraft? d = await showAddLimitSheet(context, initialPart: part);
    if (d == null) {
      return;
    }
    final String id = await _about.addLimit(part: d.part, title: d.title, status: d.status);
    if (mounted) {
      setState(() => _selected = d.part);
      final Limit? l = _about.limit(id);
      if (l != null) {
        _openLimit(l);
      }
    }
  }

  Map<String, LimitMark> _marks(AboutMe data) {
    final Map<String, LimitMark> m = <String, LimitMark>{};
    for (final Limit l in data.limits) {
      if (l.cleared) {
        continue;
      }
      final LimitMark mark = l.status == 'active' ? LimitMark.active : LimitMark.improving;
      if (m[l.part] != LimitMark.active) {
        m[l.part] = mark;
      }
    }
    return m;
  }

  Widget _partCard(AboutMe data, String key) {
    final Limit? l = data.limitForPart(key);
    if (l != null) {
      final String rules = l.rules.take(2).map((LimitRule r) => r.text).join('. ');
      return PartCard(
        title: l.title,
        status: l.status,
        statusLabel: statusLabel(l.status),
        text: rules,
        actionLabel: 'Rules, history and records ›',
        onAction: () => _openLimit(l),
      );
    }
    final String? muscle = muscleOf(key);
    return PartCard(
      title: partLabel(key),
      text: muscle == null ? 'No limit here.' : loadWords(data.loadFor(_days)[muscle] ?? 0),
      actionLabel: 'Add a limit here',
      onAction: () => _addLimit(part: key),
    );
  }

  /// The programs of the person (any status) and the row for a new one.
  Widget _programs(AppDeps d) {
    return ListenableBuilder(
      listenable: d.programs,
      builder: (BuildContext context, Widget? child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SectionHeader(title: 'Programs'),
            for (final Program p in d.programs.programs) ...<Widget>[
              ProgramRow(
                key: ValueKey<String>('program-item-${p.programId}'),
                title: p.title,
                subtitle: programShortLine(p),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (BuildContext c) => ProgramScreen(deps: d, programId: p.programId),
                )),
              ),
              const SizedBox(height: 10),
            ],
            KeyedSubtree(
              key: const ValueKey<String>('program-new'),
              child: NewKindRow(
                label: 'New program',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (BuildContext c) => ProgramNewScreen(deps: d),
                )),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _about,
      builder: (BuildContext context, Widget? child) {
        final AboutMe data = _about.data;
        final String? sel = _selected;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('What the coach knows', style: OG.muted(size: 15, weight: FontWeight.w500)),
                          Text('About me', style: OG.display(32)),
                        ],
                      ),
                    ),
                    OgIconButton(icon: Icons.close, onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: 16),
                SegmentedToggle(
                  labels: const <String>['Last 14 days', 'Last 3 months'],
                  selectedIndex: _days == 14 ? 0 : 1,
                  onChanged: (int i) => setState(() => _days = i == 0 ? 14 : 90),
                ),
                const SizedBox(height: 12),
                if (_about.error != null) ...<Widget>[
                  NoteBox(title: 'About me is not available.', message: _about.error!),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
                  decoration: ogBox(),
                  child: BodyFigure(
                    load: data.loadFor(_days),
                    limits: _marks(data),
                    focus: data.focusParts.toSet(),
                    selected: sel,
                    onTap: (String k) => setState(() => _selected = k),
                  ),
                ),
                if (sel != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _partCard(data, sel),
                ],
                const Footnote('Tap a body part to see what the coach knows about it.'),
                SectionHeader(title: 'Limits', action: '+ Add', onAction: () => _addLimit()),
                if (data.limits.isEmpty)
                  NoteBox(
                    title: _about.loading ? 'Loading…' : 'No limits yet.',
                    message: 'A limit is a body part you train around. Add one, or tap the figure.',
                  ),
                for (final Limit l in data.limits) ...<Widget>[
                  LimitCard(
                    title: l.title,
                    summary: l.rules.take(2).map((LimitRule r) => r.text).join('. '),
                    status: l.status,
                    statusLabel: statusLabel(l.status),
                    feelings: <String>[
                      for (final Checkin c in l.checkins.take(7).toList().reversed) c.feeling,
                    ],
                    onTap: () => _openLimit(l),
                  ),
                  const SizedBox(height: 10),
                ],
                if (widget.deps != null) _programs(widget.deps!),
                AboutPreferences(notes: widget.notes),
                const Footnote('The coach uses everything on this screen. It never changes your log.'),
              ],
            ),
          ),
        );
      },
    );
  }
}
