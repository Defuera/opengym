import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/about_store.dart';
import '../stores/connection_store.dart';
import '../theme.dart';
import '../widgets/nav_bar.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/review_card.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/status_line.dart';
import 'about_me_screen.dart';
import 'dashboard_view.dart';
import 'limit_ask_bar.dart';
import 'entry_screen.dart';
import 'goals_screen.dart';
import 'home_recent.dart';
import 'home_summary.dart';
import 'import_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';
import 'plus_sheet.dart';
import 'threads_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.deps});

  final AppDeps deps;

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
    _all = Listenable.merge(<Listenable>[d.store, d.connection, d.dashboard, d.reviews, d.outbox, d.entries]);
    // The dashboard is a live subscription: no refresh, no load on connect.
    d.dashboard.select(_period);
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
    _push(SessionScreen(store: widget.deps.store));
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

  /// The server draws the dashboard, but it does not know the notes. With
  /// notes present, the app draws the recent list itself, from the sessions
  /// and the notes by time, in place of the server's list.
  Widget _body() {
    final AppDeps d = widget.deps;
    final Dashboard? dash = d.dashboard.current;
    final List<LogEntry> notes = d.entries.entries;
    if (d.connection.connected && dash != null && dash.modules.isNotEmpty) {
      return DashboardView(
        dashboard: dash,
        recent: notes.isEmpty
            ? null
            : HomeRecent(sessions: d.store.sessions, entries: notes, onOpenEntry: _openEntry),
      );
    }
    return HomeSummary(
      sessions: d.store.sessions,
      period: _period,
      entries: notes,
      onOpenEntry: _openEntry,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _all,
      builder: (BuildContext context, Widget? child) {
        final AppDeps d = widget.deps;
        final Session? a = d.store.active;
        final Review? review = d.reviews.current;
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
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          OgIconButton(
                            icon: Icons.person_outline,
                            onPressed: () => _push(AboutMeScreen(
                              about: d.about,
                              notes: d.context,
                              exercises: AboutStore.knownExercises(<String>[
                                for (final Session s in d.store.sessions)
                                  for (final Exercise e in s.exercises) e.name,
                              ]),
                            )),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
                            icon: Icons.flag_outlined,
                            onPressed: () => _push(GoalsScreen(deps: d)),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
                            icon: Icons.file_upload_outlined,
                            onPressed: () => _push(ImportScreen(deps: d)),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
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
                      const SizedBox(height: 18),
                      Text('How am I doing?', style: OG.display(40)),
                      const SizedBox(height: 18),
                      LimitAskBar(about: d.about),
                      if (review != null) ...<Widget>[
                        ReviewCard(
                          summary: review.summary,
                          changes: review.changes,
                          onDismiss: d.reviews.dismiss,
                        ),
                        const SizedBox(height: 18),
                      ],
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
