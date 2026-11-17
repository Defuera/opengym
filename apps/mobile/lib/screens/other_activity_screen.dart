import 'package:flutter/material.dart';

import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/cta_button.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_chip.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/stepper_row.dart';

/// The small log form of a time/distance activity: minutes, distance, session
/// type and a note. [activity] is the name (from the log or typed). [focus]
/// and [minutes] prefill the form (e.g. from a coach proposal).
class OtherActivityScreen extends StatefulWidget {
  const OtherActivityScreen({
    super.key,
    required this.store,
    required this.activity,
    this.focus,
    this.minutes,
  });

  final AppStore store;
  final String activity;
  final String? focus;
  final int? minutes;

  @override
  State<OtherActivityScreen> createState() => _OtherActivityScreenState();
}

class _OtherActivityScreenState extends State<OtherActivityScreen> {
  late int _min;
  final TextEditingController _focus = TextEditingController();
  final TextEditingController _km = TextEditingController();
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final int m = widget.minutes ?? 30;
    _min = m < 5 ? 5 : m;
    _focus.text = widget.focus ?? advisedActivityFocus(widget.store.sessions, widget.activity) ?? '';
  }

  @override
  void dispose() {
    _focus.dispose();
    _km.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The session types logged before for this activity.
  List<String> _suggestions() => activityFoci(widget.store.sessions, widget.activity);

  void _setFocus(String text) => setState(() => _focus.text = text);

  void _log() {
    final double? km = double.tryParse(_km.text.trim().replaceAll(',', '.'));
    widget.store.logActivity(
      widget.activity,
      _min,
      focus: _focus.text,
      distanceKm: km,
      note: _note.text,
    );
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
                        child: Text(
                          widget.activity,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OG.display(32),
                        ),
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
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Distance in km (optional)',
                    controller: _km,
                    hint: 'For example 5.2',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Session type (optional)',
                    controller: _focus,
                    hint: 'For example Easy or Intervals',
                    onChanged: (String v) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String f in _suggestions())
                        OgChip(
                          label: f,
                          selected: _focus.text.trim() == f,
                          onTap: () => _setFocus(f),
                        ),
                      if (_focus.text.isNotEmpty)
                        OgChip(label: 'Clear', selected: false, onTap: () => _setFocus('')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'Note (optional)',
                    controller: _note,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: CtaButton(
                label: 'Log ${widget.activity.toLowerCase()}',
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
