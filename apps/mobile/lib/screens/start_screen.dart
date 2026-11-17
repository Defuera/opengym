import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/plan_store.dart';
import '../theme.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/prediction_card.dart';
import 'import_screen.dart';
import 'other_activity_screen.dart';
import 'prepare_session_screen.dart';
import 'session_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late final Listenable _all;

  @override
  void initState() {
    super.initState();
    final AppDeps d = widget.deps;
    _all = Listenable.merge(<Listenable>[d.store, d.plans, d.connection]);
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext c) => screen),
    );
  }

  void _begin(String type) {
    final AppDeps d = widget.deps;
    // An open session is resumed; offline starts straight from the local plan.
    if (d.store.active != null || !d.connection.connected) {
      d.store.begin(type);
      _push(SessionScreen(store: d.store));
      return;
    }
    _push(PrepareSessionScreen(deps: d, type: type));
  }

  void _choose(Prediction p) {
    if (p.kind == 'activity') {
      _push(OtherActivityScreen(store: widget.deps.store, initial: p.type));
    } else {
      _begin(p.type);
    }
  }

  String _title(Prediction p) => p.kind == 'gym' ? 'Gym · ${p.type}' : p.type;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _all,
      builder: (BuildContext context, Widget? child) {
        final AppDeps d = widget.deps;
        final List<Prediction> local = localPredictions(d.store.sessions);
        final List<Prediction> p =
            d.connection.connected ? d.plans.predictionsFor(d.store.sessions) : local;
        final List<Prediction> list = p.isEmpty ? local : p;
        final Prediction first = list.first;
        final List<Widget> options = <Widget>[];
        for (int i = 1; i < list.length && i < 5; i++) {
          final Prediction x = list[i];
          options.add(OptionCard(
            number: '${i + 1}',
            title: _title(x),
            subtitle: x.reason,
            onTap: () => _choose(x),
          ));
        }
        options.add(OptionCard(
          title: 'Other activity',
          icon: Icons.directions_run,
          onTap: () => _push(OtherActivityScreen(store: d.store)),
        ));
        options.add(OptionCard(
          icon: Icons.photo_camera_outlined,
          title: 'Import photo or file',
          onTap: () => _push(ImportScreen(deps: d)),
        ));
        options.add(OptionCard(
          icon: Icons.add,
          title: 'Empty gym session',
          dashed: true,
          onTap: () => _begin('Custom'),
        ));
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('Start', style: OG.muted(weight: FontWeight.w600)),
                    ),
                    OgIconButton(
                      icon: Icons.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('What are you about to do?', style: OG.display(40)),
                const SizedBox(height: 18),
                Text('Most likely first, from your log.', style: OG.muted()),
                const SizedBox(height: 18),
                PredictionCard(
                  rankLabel: '1 · Most likely',
                  title: _title(first),
                  subtitle: first.reason.isEmpty ? 'Session ready to follow' : first.reason,
                  onTap: () => _choose(first),
                ),
                const SizedBox(height: 18),
                OptionGrid(children: options),
              ],
            ),
          ),
        );
      },
    );
  }
}
