import 'package:flutter/material.dart';
import '../app/deps.dart';
import '../models.dart';
import '../data/convex_client.dart';
import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/og_sheet.dart';
import '../widgets/preparing_card.dart';
import '../widgets/proposal_feedback.dart';
import '../widgets/session_meta_row.dart';
import '../stores/exercise_art_store.dart';
import '../stores/proposal_rebuild.dart';
import 'place_mark_view.dart';
import 'session_parts.dart';
import 'session_recap_screen.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.store,
    this.deps,
    this.rebuild,
  });

  final AppStore store;

  /// With [deps], finishing a session ends on its recap. Without, on Home.
  final AppDeps? deps;

  /// Set on a coach proposal: "Change plan" shows until a set is done.
  final ProposalRebuild? rebuild;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver {
  final TextEditingController _feedback = TextEditingController();
  bool _wasBusy = false;

  /// What the planned session works (muscle key -> level), for the figure at
  /// the title. Null until known, and offline.
  Map<String, int>? _load;
  String? _loadKey;
  String _artNames = '';

  /// Which side the card of the current exercise comes in from: 1 right, -1 left.
  /// Zero until the person changes the exercise: the first card does not move.
  double _from = 0;
  late int _lastEx = store.curEx;

  /// A sideways swipe on the card shows the next or the previous exercise.
  void _onSwipe(DragEndDetails d) {
    final double v = d.primaryVelocity ?? 0;
    final int count = store.active?.exercises.length ?? 0;
    final int to = store.curEx + (v < -250 ? 1 : (v > 250 ? -1 : 0));
    if (to != store.curEx && to >= 0 && to < count) {
      store.pickExercise(to);
    }
  }

  AppStore get store => widget.store;
  AppDeps? get deps => widget.deps;
  ProposalRebuild? get rebuild => widget.rebuild;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    rebuild?.addListener(_onRebuild);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rebuild?.removeListener(_onRebuild);
    _feedback.dispose();
    super.dispose();
  }

  /// After the phone was locked or the app was in the background, the
  /// countdown checks its end time at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      store.countdown.tick();
    }
  }

  /// The typed text is cleared after a rebuild went through, kept after a failure.
  void _onRebuild() {
    final ProposalRebuild r = rebuild!;
    if (_wasBusy && !r.busy && !r.failed) {
      _feedback.clear();
    }
    _wasBusy = r.busy;
  }

  void _minimise(BuildContext context) {
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
  }

  /// Asks for the pictures of the session's exercises when the list changes.
  /// After the frame, so the store never notifies while the screen builds.
  void _trackArt(Session a) {
    final ExerciseArtStore? art = deps?.art;
    if (art == null) {
      return;
    }
    final List<String> names = <String>[for (final Exercise e in a.exercises) e.name];
    final String sig = '${deps?.connection.connected}|${names.join('\u0000')}';
    if (sig == _artNames) {
      return;
    }
    _artNames = sig;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        art.track(names);
      }
    });
  }

  /// The planned load of the session. Null when offline, not set up, or on any failure.
  Future<Map<String, int>?> _planLoad(Session a) async {
    final AppDeps? d = deps;
    if (d == null || !d.connection.connected || a.exercises.isEmpty) {
      return null;
    }
    try {
      return await d.client.planLoad(<PlanLoadItem>[
        for (final Exercise e in a.exercises)
          PlanLoadItem(
            name: e.name,
            sets: e.isTime ? 0 : e.sets.length,
            minutes: e.isTime ? e.sets.fold<double>(0, (double s, SetEntry x) => s + (x.minutes ?? 0)) : 0,
          ),
      ]);
    } catch (_) {
      return null;
    }
  }

  /// Reads the load again when the exercises or their set counts change.
  void _trackLoad(Session a) {
    final String key =
        '${a.id}|${deps?.connection.connected}|${a.exercises.map((Exercise e) => '${e.name}:${e.sets.length}').join(',')}';
    if (key == _loadKey) {
      return;
    }
    _loadKey = key;
    _planLoad(a).then((Map<String, int>? v) {
      if (mounted && _loadKey == key) {
        setState(() => _load = v);
      }
    });
  }

  Future<void> _showWhy(BuildContext context, Session a) {
    final Future<Map<String, int>?> load = _planLoad(a);
    return showOgSheet<void>(
      context,
      (BuildContext c) => FutureBuilder<Map<String, int>?>(
        future: load,
        builder: (BuildContext c, AsyncSnapshot<Map<String, int>?> s) =>
            WhySessionBody(focus: a.focus, rationale: a.planNote, load: s.data),
      ),
      title: 'Why this session',
    );
  }

  Future<void> _showChangePlan(BuildContext context) {
    final ProposalRebuild r = rebuild!;
    return showOgSheet<void>(
      context,
      (BuildContext c) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable?>[r, deps?.connection].whereType<Listenable>().toList()),
        builder: (BuildContext c, Widget? w) => ProposalFeedback(
          controller: _feedback,
          failed: r.failed,
          online: deps?.connection.connected ?? true,
          onRebuild: (String t) {
            Navigator.of(c).pop();
            r.rebuild(t);
          },
        ),
      ),
      title: 'Change plan',
    );
  }

  void _leave(BuildContext context, {String? recapId}) {
    final NavigatorState nav = Navigator.of(context);
    nav.popUntil((Route<dynamic> r) => r.isFirst);
    final AppDeps? d = deps;
    if (recapId != null && d != null) {
      nav.push(MaterialPageRoute<void>(
        builder: (BuildContext c) => SessionRecapScreen(deps: d, sessionId: recapId),
      ));
    }
  }

  /// The one way out: Pause, Finish (with a done set) or Discard. Closing the
  /// sheet stays in the session.
  /// The one confirm step before a session is finished. It says what is left
  /// out: sets that are not done are not saved. True only on "Finish and save".
  Future<bool> _confirmFinish(BuildContext context) async {
    int open = 0;
    for (final Exercise e in store.active?.exercises ?? <Exercise>[]) {
      open += e.sets.where((SetEntry s) => !s.done).length;
    }
    final String? c = await showChoiceSheet(
      context,
      title: 'Finish this session?',
      message: open == 0
          ? 'Every set is done.'
          : open == 1
              ? '1 set is not done. It is not saved.'
              : '$open sets are not done. They are not saved.',
      choices: const <SheetChoice>[
        SheetChoice(
          value: 'finish',
          label: 'Finish and save',
          variant: OgVariant.accent,
          key: ValueKey<String>('confirm-finish'),
        ),
        SheetChoice(value: 'stay', label: 'Keep going', variant: OgVariant.dashed),
      ],
    );
    return c == 'finish';
  }

  /// The bottom button: asks first, then finishes and opens the recap.
  Future<void> _finishFromButton(BuildContext context) async {
    if (!await _confirmFinish(context) || !context.mounted) {
      return;
    }
    _leave(context, recapId: store.finish());
  }

  Future<void> _askLeave(BuildContext context) async {
    final String? choice = await showChoiceSheet(
      context,
      title: 'Leave this session?',
      choices: <SheetChoice>[
        const SheetChoice(
          value: 'pause',
          label: 'Pause, come back later',
          variant: OgVariant.accent,
        ),
        if (store.hasDoneSet) const SheetChoice(value: 'finish', label: 'Finish and save'),
        const SheetChoice(value: 'discard', label: 'Discard session', variant: OgVariant.dashed),
      ],
    );
    String? saved;
    if (choice == 'pause') {
      if (context.mounted) {
        _minimise(context);
      }
      return;
    } else if (choice == 'finish') {
      if (!context.mounted || !await _confirmFinish(context)) {
        return;
      }
      saved = store.finish();
    } else if (choice == 'discard') {
      if (!context.mounted) {
        return;
      }
      final bool ok = await confirmDelete(
        context,
        title: 'Discard this session?',
        label: 'Discard session',
      );
      if (!ok) {
        return;
      }
      store.discard();
    } else {
      return;
    }
    if (context.mounted) {
      _leave(context, recapId: saved);
    }
  }

  Future<void> _addExercise(BuildContext context) async {
    final Session? a = store.active;
    if (a == null) {
      return;
    }
    final ExerciseChoice? pick = await showExercisePicker(
      context,
      title: 'Add exercise',
      options: <ExerciseOption>[
        for (final LoggedExercise x in loggedExercises(store.sessions))
          ExerciseOption(x.name, timed: x.measure == measureTime),
      ],
    );
    if (pick == null || pick.name.isEmpty) {
      return;
    }
    store.addExercise(pick.name, measure: pick.timed ? measureTime : measureSets);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable?>[store, rebuild, deps?.connection].whereType<Listenable>().toList()),
      builder: (BuildContext context, Widget? child) {
        final Session? a = store.active;
        if (a == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        _trackArt(a);
        _trackLoad(a);
        if (store.curEx != _lastEx) {
          _from = store.curEx > _lastEx ? 1 : -1;
          _lastEx = store.curEx;
        }
        final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        final bool canChange = rebuild != null && !store.hasDoneSet;
        final bool busy = canChange && rebuild!.busy;
        final bool why = a.focus != null || a.planNote != null || a.exercises.isNotEmpty;
        return PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (!didPop) {
                _askLeave(context);
              }
            },
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          KeyedSubtree(
                            key: const ValueKey<String>('leave-back'),
                            child: OgIconButton(
                              icon: Icons.arrow_back,
                              onPressed: () => _askLeave(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                a.type,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: OG.display(a.type.length > 24 ? 26 : 30),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (a.focus != null && a.focus!.isNotEmpty) ...<Widget>[
                                  Text(
                                    a.focus!,
                                    key: const ValueKey<String>('session-focus'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: OG.body(size: 16, weight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                SessionMetaRow(
                                  note: (rebuild?.failed ?? false) && !busy
                                      ? 'Could not rebuild. Try again.'
                                      : canChange && !busy
                                          ? (rebuild!.offer != null
                                              ? 'The plan of the coach is ready.'
                                              : rebuild!.notice)
                                          : null,
                                  items: <Widget>[
                                    if (deps != null)
                                      PlaceMarkView(
                                          deps: deps!, placeId: a.placeId, onPick: store.setActivePlace, chip: true),
                                    if (canChange)
                                      MetaItem(
                                          label: 'Change plan',
                                          icon: Icons.tune,
                                          onTap: () => _showChangePlan(context)),
                                    if (canChange && !busy && rebuild!.offer != null)
                                      MetaItem(
                                        key: const ValueKey<String>('use-coach-plan'),
                                        label: 'Use the coach plan',
                                        icon: Icons.auto_awesome_outlined,
                                        onTap: rebuild!.useOffer,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (why) ...<Widget>[
                            const SizedBox(width: 12),
                            WhyFigureButton(
                              key: const ValueKey<String>('why-icon'),
                              load: _load,
                              onTap: () => _showWhy(context, a),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (busy)
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: PreparingCard(
                            title: 'Rebuilding…',
                            message: 'The coach changes the session with your feedback.',
                            actionLabel: 'Keep this session',
                            onAction: rebuild!.cancel,
                          ),
                        ),
                      )
                    else ...<Widget>[
                      ExerciseStrip(
                        store: store,
                        onAdd: () => _addExercise(context),
                      ),
                      Expanded(
                        child: GestureDetector(
                          key: const ValueKey<String>('panel-swipe'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragEnd: _onSwipe,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey<String>('panel-${store.currentExercise?.id}'),
                              tween: Tween<double>(begin: _from == 0 ? 0 : 1, end: 0),
                              duration: still ? Duration.zero : const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              builder: (BuildContext c, double t, Widget? child) => Opacity(
                                opacity: 1 - t,
                                child: Transform.translate(offset: Offset(_from * 48 * t, 0), child: child),
                              ),
                              child: deps == null
                                  ? SessionPanel(store: store)
                                  : ListenableBuilder(
                                      listenable: deps!.art,
                                      builder: (BuildContext c, Widget? w) =>
                                          SessionPanel(store: store, art: deps!.art),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    _bottomButton(context, a),
                  ],
                ),
              ),
            ));
      },
    );
  }

  /// A button shows only when every set of the current exercise is done.
  Widget _bottomButton(BuildContext context, Session a) {
    final Exercise? ex = store.currentExercise;
    final bool last = store.curEx >= a.exercises.length - 1;
    if (ex != null && !allDone(ex)) {
      return const SizedBox(height: 8);
    }
    final bool next = ex != null && !last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: SizedBox(
        width: double.infinity,
        child: OgButton(
          key: ValueKey<String>(next ? 'next-exercise' : 'finish-session'),
          variant: OgVariant.ink,
          onPressed: next ? store.nextExercise : () => _finishFromButton(context),
          child: Text(next ? 'Next exercise' : 'Finish session', style: OG.display(20, color: OG.white)),
        ),
      ),
    );
  }
}
