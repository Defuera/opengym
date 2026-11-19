import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../planner.dart';
import '../session_text.dart';
import '../stores/review_store.dart';
import '../stores/session_load_store.dart';
import '../theme.dart';
import '../widgets/body_figure.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/recap_exercise_card.dart';
import '../widgets/review_card.dart';
import 'place_mark_view.dart';
import 'session_edit_screen.dart';

/// A finished session: what was done, set by set, the note, the coach's
/// review and the body figure of what it loaded. Edit and Delete are here.
/// It reads the store, so a change from the edit screen shows at once.
class SessionRecapScreen extends StatefulWidget {
  const SessionRecapScreen({super.key, required this.deps, required this.sessionId});

  final AppDeps deps;
  final String sessionId;

  @override
  State<SessionRecapScreen> createState() => _SessionRecapScreenState();
}

class _SessionRecapScreenState extends State<SessionRecapScreen> {
  late final ReviewStore _review = ReviewStore(client: widget.deps.client)..watch(widget.sessionId);
  late final SessionLoadStore _load = SessionLoadStore(client: widget.deps.client)
    ..watch(widget.sessionId);

  @override
  void dispose() {
    _review.dispose();
    _load.dispose();
    super.dispose();
  }

  Future<void> _edit(Session s) {
    return Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (BuildContext c) => SessionEditScreen(deps: widget.deps, session: s),
      ),
    );
  }

  Future<void> _delete() async {
    final bool ok = await confirmDelete(
      context,
      title: 'Delete this session?',
      label: 'Delete session',
      message: 'It is removed from your log now and erased for good after 72 hours.',
    );
    if (!ok) {
      return;
    }
    widget.deps.store.removeSession(widget.sessionId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Edit and Delete live behind the menu button at the top right.
  Future<void> _menu(Session s) async {
    final String? c = await showChoiceSheet(
      context,
      title: 'Session',
      choices: const <SheetChoice>[
        SheetChoice(value: 'edit', label: 'Edit', key: ValueKey<String>('recap-edit')),
        SheetChoice(value: 'delete', label: 'Delete', variant: OgVariant.dashed, key: ValueKey<String>('recap-delete')),
      ],
    );
    if (!mounted) {
      return;
    }
    if (c == 'edit') {
      _edit(s);
    } else if (c == 'delete') {
      await _delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.deps.store, _review, _load]),
      builder: (BuildContext context, Widget? child) {
        final Session? s = widget.deps.store.sessionById(widget.sessionId);
        return Scaffold(
          body: SafeArea(
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
                    Expanded(child: Text('Session', style: OG.display(32))),
                    if (s != null)
                      OgIconButton(
                        key: const ValueKey<String>('recap-menu'),
                        icon: Icons.more_horiz,
                        onPressed: () => _menu(s),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (s == null)
                  const NoteBox(title: 'This session is gone.', message: 'It was deleted.')
                else
                  ..._body(s),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(Session s) {
    final bool gym = s.kind == 'gym';
    final String? focus = s.focus;
    final String? note = s.note?.trim();
    final Review? review = _review.current;
    final Map<String, int>? load = _load.load;
    final double? km = s.distanceKm;
    // A session logged as one text has no length of its own until the text is read.
    final bool spanKnown = (s.endedAt ?? s.startedAt) > s.startedAt;
    final bool showTimes = hasRealTimes(s) && spanKnown;
    return <Widget>[
      Text(s.type, key: const ValueKey<String>('recap-type'), style: OG.display(28)),
      if (focus != null && focus.isNotEmpty)
        Text(focus, key: const ValueKey<String>('recap-focus'), style: OG.muted(weight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(
        showTimes
            ? '${sessionDate(s)} · ${sessionStart(s)} · ${sessionDuration(s)}'
            : sessionDate(s),
        key: const ValueKey<String>('recap-when'),
        style: OG.muted(),
      ),
      PlaceMarkView(
        deps: widget.deps,
        placeId: s.placeId,
        onPick: (String id) => widget.deps.store.setSessionPlace(s.id, id),
      ),
      const SizedBox(height: 10),
      if (s.parsePending)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Reading your text…', key: const ValueKey<String>('recap-parsing'), style: OG.muted()),
        ),
      if (!gym && (s.minutes != null || km != null || spanKnown))
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: ogBox(shadow: false),
          child: Text(
            '${s.minutes ?? sessionMinutes(s)} min${km == null ? '' : ', ${fmtKg(km)} km'}',
            key: const ValueKey<String>('recap-activity'),
            style: OG.body(size: 18, weight: FontWeight.w700),
          ),
        ),
      for (final Exercise e in s.exercises) ...<Widget>[
        RecapExerciseCard(name: e.name, lines: <String>[for (final SetEntry x in e.sets) setLine(x)]),
        const SizedBox(height: 10),
      ],
      if (note != null && note.isNotEmpty) ...<Widget>[
        const SizedBox(height: 6),
        Text('Note', style: OG.muted(size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(note, key: const ValueKey<String>('recap-note'), style: OG.body()),
        const SizedBox(height: 16),
      ],
      if (review != null) ...<Widget>[
        const SizedBox(height: 6),
        ReviewCard(title: 'Coach review', summary: review.summary, changes: review.changes),
        const SizedBox(height: 16),
      ],
      if (load != null && load.values.any((int v) => v > 0)) ...<Widget>[
        Text('What it worked', style: OG.display(24)),
        const SizedBox(height: 10),
        BodyFigure(key: const ValueKey<String>('recap-figure'), load: load, loadOnly: true, onTap: (String _) {}),
        const SizedBox(height: 16),
      ],
    ];
  }
}
