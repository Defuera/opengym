import 'package:flutter/material.dart';

import '../planner.dart';
import '../store.dart';
import '../theme.dart';
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
                      SizedBox(
                        width: 52,
                        child: OgButton(
                          minHeight: 52,
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Icon(Icons.chevron_left, size: 28),
                        ),
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
                      for (final String n in activities) _chip(n),
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
              child: SizedBox(
                width: double.infinity,
                child: OgButton(
                  variant: OgVariant.accent,
                  minHeight: 76,
                  radius: 20,
                  onPressed: _log,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.check, size: 30),
                      const SizedBox(width: 8),
                      Text(
                        'Log ${_act.toLowerCase()}',
                        style: OG.display(24, color: OG.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String name) {
    final bool on = _act == name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _act = name),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? OG.ink : OG.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: OG.ink, width: 2),
        ),
        child: Text(
          name,
          style: OG.body(
            weight: FontWeight.w600,
            color: on ? OG.white : OG.ink,
          ),
        ),
      ),
    );
  }
}
