import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../home_data.dart';
import '../models.dart';
import '../stores/about_store.dart';
import '../stores/connection_store.dart';
import '../theme.dart';
import '../widgets/nav_bar.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/status_line.dart';
import 'about_me_screen.dart';
import 'limit_ask_bar.dart';
import 'entry_screen.dart';
import 'goals_screen.dart';
import 'home_summary.dart';
import 'import_screen.dart';
import 'session_recap_screen.dart';
import 'session_screen.dart';
import 'start_flow.dart';
import 'settings_screen.dart';
import 'plus_sheet.dart';
import 'threads_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.deps, this.nowMs});

  final AppDeps deps;

  /// The clock for the blocks; null is the real time. Tests set it.
  final int? nowMs;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _period = 7;
  late final Listenable _all;

  @override
  void initState() {
    super.initState();
    final AppDeps d = widget.deps;
    _all = Listenable.merge(<Listenable>[d.store, d.connection, d.dashboard, d.reviews, d.outbox, d.entries, d.goals]);
    // The dashboard is a live subscription: no refresh, no load on connect.
    d.dashboard.select(_period);
    // The review of the latest session shows from the start. A session that
    // was just saved is watched by compose; this covers a fresh launch.
    final Session? last = lastSession(d.store.sessions);
    if (d.reviews.current == null && last != null) {
      d.reviews.watch(last.id);
    }
  }

  void _setPeriod(int days) {
    setState(() => _period = days);
    widget.deps.dashboard.select(days);
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext c) => screen),
    );
  }

  void _resume() {
    widget.deps.store.resume();
    _push(SessionScreen(store: widget.deps.store, deps: widget.deps, rebuild: rebuildFor(widget.deps)));
  }

  String get _statusText {
    switch (widget.deps.connection.state) {
      case ConnState.connected:
        return 'Connected';
      case ConnState.connecting:
        return 'Connecting...';
      case ConnState.unauthorized:
        return 'Token not accepted: check Settings';
      case ConnState.badUrl:
        return 'Server address is not valid: check Settings';
      case ConnState.notConfigured:
        return 'No server set: saved on this phone';
      case ConnState.offline:
        final int n = widget.deps.outbox.length;
        return n == 0 ? 'Offline: saved on this phone' : 'Offline: saved on this phone, $n to send';
    }
  }

  void _openEntry(LogEntry e) {
    _push(EntryScreen(deps: widget.deps, entryId: e.id));
  }

  void _openSession(Session s) {
    _push(SessionRecapScreen(deps: widget.deps, sessionId: s.id));
  }

  /// The blocks come from data on the phone; the server's dashboard adds the
  /// modules they do not cover. Notes join the recent list, by time.
  Widget _body() {
    final AppDeps d = widget.deps;
    return HomeSummary(
      sessions: d.store.sessions,
      period: _period,
      goals: d.goals.goals,
      dashboard: d.connection.connected ? d.dashboard.current : null,
      review: d.reviews.current,
      entries: d.entries.entries,
      onOpenEntry: _openEntry,
      onOpenSession: _openSession,
      nowMs: widget.nowMs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _all,
      builder: (BuildContext context, Widget? child) {
        final AppDeps d = widget.deps;
        final Session? a = d.store.active;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(child: Text('How am I doing?', style: OG.display(30))),
                          const SizedBox(width: 8),
                          OgIconButton(
                            size: 44,
                            icon: Icons.person_outline,
                            onPressed: () => _push(AboutMeScreen(
                              about: d.about,
                              notes: d.context,
                              deps: d,
                              exercises: AboutStore.knownExercises(<String>[
                                for (final Session s in d.store.sessions)
                                  for (final Exercise e in s.exercises) e.name,
                              ]),
                            )),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
                            size: 44,
                            icon: Icons.flag_outlined,
                            onPressed: () => _push(GoalsScreen(deps: d)),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
                            size: 44,
                            icon: Icons.file_upload_outlined,
                            onPressed: () => _push(ImportScreen(deps: d)),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
                            size: 44,
                            icon: Icons.settings_outlined,
                            onPressed: () => _push(SettingsScreen(deps: d)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SegmentedToggle(
                        labels: const <String>['Last week', 'Last month'],
                        selectedIndex: _period == 7 ? 0 : 1,
                        onChanged: (int i) => _setPeriod(i == 0 ? 7 : 30),
                      ),
                      const SizedBox(height: 16),
                      LimitAskBar(about: d.about),
                      if (a != null) ...<Widget>[
                        OgButton(
                          variant: OgVariant.ink,
                          onPressed: _resume,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  a.focus == null ? 'Resume ${a.type} session' : 'Resume ${a.type} · ${a.focus} session',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 22),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      _body(),
                      const SizedBox(height: 18),
                      StatusLine(
                        text: _statusText,
                        connected: d.connection.connected,
                      ),
                    ],
                  ),
                ),
                NavBar(
                  onHome: () {},
                  onPlus: () => showPlusSheet(context, d),
                  onChat: () => _push(ThreadsScreen(deps: d)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
