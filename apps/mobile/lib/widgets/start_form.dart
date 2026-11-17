import 'package:flutter/material.dart';

import '../theme.dart';
import 'labeled_field.dart';
import 'og_button.dart';
import 'sheet_link.dart';

/// The small form of the Start tab: a name and an optional wish, then
/// "Prepare session" and "Start empty". The fields scroll; the buttons stay in
/// view above the keyboard. With [lockedName] the name is fixed (read only).
class StartForm extends StatefulWidget {
  const StartForm({
    super.key,
    required this.name,
    required this.wish,
    required this.onBack,
    required this.onPrepare,
    required this.onStartEmpty,
    this.lockedName,
  });

  final TextEditingController name;
  final TextEditingController wish;
  final String? lockedName;
  final VoidCallback onBack;
  final VoidCallback onPrepare;
  final VoidCallback onStartEmpty;

  @override
  State<StartForm> createState() => _StartFormState();
}

class _StartFormState extends State<StartForm> {
  // Shows the locked name in the (read only) name field.
  late final TextEditingController _lockedCtl = TextEditingController(text: widget.lockedName);

  @override
  void didUpdateWidget(StartForm old) {
    super.didUpdateWidget(old);
    _lockedCtl.text = widget.lockedName ?? '';
  }

  @override
  void dispose() {
    _lockedCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? lockedName = widget.lockedName;
    final TextEditingController nameCtl = lockedName == null ? widget.name : _lockedCtl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Back',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: OG.ink),
            ),
            Expanded(
              child: Text(
                lockedName == null ? 'New kind of session' : 'Custom session',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OG.display(24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                LabeledField(
                  label: 'Name',
                  controller: nameCtl,
                  hint: 'Home',
                  maxLength: 40,
                  readOnly: lockedName != null,
                  autocorrect: true,
                  textInputAction: TextInputAction.next,
                  helper: 'It appears in your list next time.',
                ),
                const SizedBox(height: 14),
                LabeledField(
                  label: 'What do you want? (optional)',
                  controller: widget.wish,
                  hint: '15 minutes, no equipment, easy on the knee',
                  maxLength: 200,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: true,
                  keyboardType: TextInputType.multiline,
                  helper: 'The coach builds the session from this, your log and your limits.',
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.name,
          builder: (BuildContext context, TextEditingValue v, Widget? child) {
            final bool ok = lockedName != null || v.text.trim().isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OgButton(
                  variant: OgVariant.accent,
                  onPressed: ok ? widget.onPrepare : null,
                  child: const Text('Prepare session'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ok
                      ? SheetLink(label: 'Start empty', onTap: widget.onStartEmpty)
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('Start empty ›', style: OG.muted(weight: FontWeight.w700).copyWith(color: OG.mute.withValues(alpha: 0.5))),
                        ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
