import 'package:flutter/material.dart';

import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/og_button.dart';
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
          options.add(_option(
            number: '${i + 1}',
            title: 'Gym · $type',
            onPressed: () => _begin(context, type),
          ));
        }
        options.add(_option(
          number: '${p.length + 1}',
          title: 'Other activity',
          onPressed: () => _other(context),
        ));
        options.add(OgButton(
          variant: OgVariant.dashed,
          minHeight: 112,
          padding: const EdgeInsets.all(14),
          alignment: Alignment.topLeft,
          onPressed: () => _begin(context, 'Custom'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Icon(Icons.add, size: 26),
              Text('Empty gym session', style: OG.display(24)),
            ],
          ),
        ));

        final List<Widget> rows = <Widget>[];
        for (int i = 0; i < options.length; i += 2) {
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: options[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < options.length ? options[i + 1] : const SizedBox(),
              ),
            ],
          ));
          rows.add(const SizedBox(height: 8));
        }

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Start',
                        style: OG.muted(weight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: OgButton(
                        minHeight: 52,
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.close, size: 24),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('What are you about to do?', style: OG.display(40)),
                const SizedBox(height: 18),
                Text('Most likely first, from your log.', style: OG.muted()),
                const SizedBox(height: 18),
                OgButton(
                  variant: OgVariant.accent,
                  minHeight: 170,
                  radius: 20,
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.topLeft,
                  onPressed: () => _begin(context, p[0].type),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              '1 · Most likely',
                              style: OG.body(
                                weight: FontWeight.w600,
                                color: OG.white,
                              ),
                            ),
                            const Icon(Icons.arrow_forward, size: 28),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Text(
                          'Gym · ${p[0].type}',
                          style: OG.display(44, color: OG.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Session ready to follow',
                          style: OG.body(
                            weight: FontWeight.w500,
                            color: OG.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ...rows,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _option({
    required String number,
    required String title,
    required VoidCallback onPressed,
  }) {
    return OgButton(
      minHeight: 112,
      padding: const EdgeInsets.all(14),
      alignment: Alignment.topLeft,
      onPressed: onPressed,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(number, style: OG.muted(weight: FontWeight.w700)),
            const SizedBox(height: 18),
            Text(title, style: OG.display(24)),
          ],
        ),
      ),
    );
  }
}
