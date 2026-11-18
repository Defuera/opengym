import 'package:flutter/material.dart';

import 'labeled_field.dart';
import 'og_button.dart';
import 'start_details.dart';

/// "Other" in the Start tab: a name (1..40) and the shape of the activity.
/// "Sets and reps" goes on to step 2; "Time or distance" opens the Log form.
/// Both stay off while the name is empty.
class StartOther extends StatelessWidget {
  const StartOther({
    super.key,
    required this.name,
    required this.onBack,
    required this.onSets,
    required this.onTime,
  });

  final TextEditingController name;
  final VoidCallback onBack;
  final VoidCallback onSets;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StartStepHeader(title: 'Other', onBack: onBack),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: LabeledField(
              label: 'Name',
              controller: name,
              hint: 'Wing SUP',
              maxLength: 40,
              autocorrect: true,
              helper: 'It appears in your list next time.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: name,
          builder: (BuildContext context, TextEditingValue v, Widget? child) {
            final bool ok = v.text.trim().isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OgButton(
                  variant: OgVariant.accent,
                  onPressed: ok ? onSets : null,
                  child: const Text('Sets and reps'),
                ),
                const SizedBox(height: 10),
                OgButton(
                  variant: OgVariant.plain,
                  onPressed: ok ? onTime : null,
                  child: const Text('Time or distance'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
