import 'package:flutter/material.dart';

import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/prediction_card.dart';
import 'other_activity_screen.dart';
import 'session_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.store});

  final AppStore store;

  void _begin(BuildContext context, String type) {
    store.begin(type);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => SessionScreen(store: store),
      ),
    );
  }

  void _other(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => OtherActivityScreen(store: store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (BuildContext context, Widget? child) {
        final List<Prediction> p = predictions(store.sessions);
        final List<Widget> options = <Widget>[];
        for (int i = 1; i < p.length; i++) {
          final String type = p[i].type;
          options.add(OptionCard(
            number: '${i + 1}',
            title: 'Gym · $type',
            onTap: () => _begin(context, type),
          ));
        }
        options.add(OptionCard(
          number: '${p.length + 1}',
          title: 'Other activity',
          onTap: () => _other(context),
        ));
        options.add(OptionCard(
          icon: Icons.add,
          title: 'Empty gym session',
          dashed: true,
          onTap: () => _begin(context, 'Custom'),
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
                  title: 'Gym · ${p[0].type}',
                  subtitle: 'Session ready to follow',
                  onTap: () => _begin(context, p[0].type),
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
