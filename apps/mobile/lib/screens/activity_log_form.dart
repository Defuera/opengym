import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../planner.dart';
import '../theme.dart';
import '../widgets/cta_button.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import 'session_recap_screen.dart';

/// The form of a time/distance activity (ADR-018): the activity name and one
/// text, "What did you do?". Nothing else. "Log" saves the session at once
/// with the text as its note and opens its recap; the server reads the text
/// into minutes, distance and exercises and the recap updates by itself.
/// It is reached only from the Start tab, when the coach answers a start
/// request with a time/distance activity. The Log tab opens the log chat.
class ActivityLogForm extends StatefulWidget {
  const ActivityLogForm({super.key, required this.deps, required this.activity});

  final AppDeps deps;

  /// The activity name (from the log or typed), at most 40 characters.
  final String activity;

  @override
  State<ActivityLogForm> createState() => _ActivityLogFormState();
}

class _ActivityLogFormState extends State<ActivityLogForm> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _log() {
    final String? id = widget.deps.store.logText(widget.activity, _text.text);
    if (id == null) {
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    nav.popUntil((Route<dynamic> r) => r.isFirst);
    nav.push(MaterialPageRoute<void>(
      builder: (BuildContext c) => SessionRecapScreen(deps: widget.deps, sessionId: id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  LabeledField(
                    label: 'What did you do?',
                    controller: _text,
                    hint: '45 min, 8 km, easy pace',
                    maxLength: maxLogTextLength,
                    minLines: 4,
                    maxLines: 10,
                    autocorrect: true,
                    keyboardType: TextInputType.multiline,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (BuildContext context, TextEditingValue v, Widget? child) {
                  return CtaButton(
                    label: 'Log',
                    icon: Icons.check,
                    variant: OgVariant.accent,
                    onPressed: v.text.trim().isEmpty ? null : _log,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
