import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/og_button.dart';
import '../widgets/plus_bar.dart';
import '../widgets/segmented_toggle.dart';
import 'home_summary.dart';
import 'session_screen.dart';
import 'start_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _period = 7;

  void _openStart() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => StartScreen(store: widget.store),
      ),
    );
  }

  void _resume() {
    widget.store.resume();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => SessionScreen(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (BuildContext context, Widget? child) {
        final AppStore store = widget.store;
        final Session? a = store.active;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: <Widget>[
                      SegmentedToggle(
                        labels: const <String>['Last week', 'Last month'],
                        selectedIndex: _period == 7 ? 0 : 1,
                        onChanged: (int i) =>
                            setState(() => _period = i == 0 ? 7 : 30),
                      ),
                      const SizedBox(height: 18),
                      Text('How am I doing?', style: OG.display(40)),
                      const SizedBox(height: 18),
                      if (a != null) ...<Widget>[
                        OgButton(
                          variant: OgVariant.ink,
                          onPressed: _resume,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  'Resume ${a.type} session',
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
                      HomeSummary(sessions: store.sessions, period: _period),
                      const SizedBox(height: 18),
                      Text('Saved on this phone.', style: OG.muted(size: 13)),
                    ],
                  ),
                ),
                PlusBar(onPressed: _openStart),
              ],
            ),
          ),
        );
      },
    );
  }
}
