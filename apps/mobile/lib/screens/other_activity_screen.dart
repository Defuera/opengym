import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/cta_button.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_chip.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/og_button.dart';
import '../widgets/stepper_row.dart';

class OtherActivityScreen extends StatefulWidget {
  const OtherActivityScreen({
    super.key,
    required this.store,
    this.initial = 'Run',
    this.predictions = const <Prediction>[],
  });

  final AppStore store;

  /// The start suggestions. An activity item may carry an advised session type.
  final List<Prediction> predictions;

  /// Activity to preselect (e.g. from a prediction).
  final String initial;

  @override
  State<OtherActivityScreen> createState() => _OtherActivityScreenState();
}

class _OtherActivityScreenState extends State<OtherActivityScreen> {
  late String _act;
  int _min = 30;
  final TextEditingController _focus = TextEditingController();

  /// True once the user typed or picked a session type; then a new activity
  /// chip no longer replaces it.
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _act = activities.contains(widget.initial) ? widget.initial : 'Other';
    _focus.text = _advised(_act) ?? '';
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// The advised session type of [act]: the server's, else from the local log.
  String? _advised(String act) {
    for (final Prediction p in widget.predictions) {
      if (p.kind == 'activity' && p.type == act && (p.focus ?? '').isNotEmpty) {
        return p.focus;
      }
    }
    return advisedActivityFocus(widget.store.sessions, act);
  }

  /// Advised first, then the ones logged before for this activity.
  List<String> _suggestions() {
    final String? a = _advised(_act);
    return <String>[
      if (a != null) a,
      ...activityFoci(widget.store.sessions, _act).where((String f) => f != a),
    ];
  }

  void _setFocus(String text) {
    setState(() {
      _edited = true;
      _focus.text = text;
    });
  }

  void _log() {
    widget.store.logActivity(_act, _min, focus: _focus.text);
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
                          onTap: () => setState(() {
                            _act = n;
                            if (!_edited) {
                              _focus.text = _advised(n) ?? '';
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Session type (optional)',
                    controller: _focus,
                    hint: 'For example Easy or Intervals',
                    onChanged: (String v) => setState(() => _edited = true),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String f in _suggestions())
                        OgChip(
                          label: f == _advised(_act) ? '$f · advised' : f,
                          selected: _focus.text.trim() == f,
                          onTap: () => _setFocus(f),
                        ),
                      if (_focus.text.isNotEmpty)
                        OgChip(label: 'Clear', selected: false, onTap: () => _setFocus('')),
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
