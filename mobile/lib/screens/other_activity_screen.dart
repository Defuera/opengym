import 'package:flutter/material.dart';

import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/cta_button.dart';
import '../widgets/og_chip.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/og_button.dart';
import '../widgets/stepper_row.dart';

class OtherActivityScreen extends StatefulWidget {
  const OtherActivityScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<OtherActivityScreen> createState() => _OtherActivityScreenState();
}

class _OtherActivityScreenState extends State<OtherActivityScreen> {
  String _act = 'Run';
  int _min = 30;

  void _log() {
    widget.store.logActivity(_act, _min);
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
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
                      Expanded(
                        child: Text('Other activity', style: OG.display(32)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String n in activities)
                        OgChip(
                          label: n,
                          selected: _act == n,
                          onTap: () => setState(() => _act = n),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: ogBox(radius: 20),
                    child: StepperRow(
                      label: 'Minutes',
                      value: '$_min',
                      onMinus: () => setState(() {
                        _min = _min - 5 < 5 ? 5 : _min - 5;
                      }),
                      onPlus: () => setState(() => _min = _min + 5),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: CtaButton(
                label: 'Log ${_act.toLowerCase()}',
                icon: Icons.check,
                variant: OgVariant.accent,
                onPressed: _log,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
