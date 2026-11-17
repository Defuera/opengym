import 'package:flutter/material.dart';

import '../theme.dart';

/// "How was the knee today?" with three answers: Fine, Noticed it, Bad.
/// [onAnswer] gets fine | noticed | bad. With [onSkip] a Skip link shows.
class FeelingCard extends StatelessWidget {
  const FeelingCard({
    super.key,
    required this.question,
    required this.onAnswer,
    this.onSkip,
    this.skipLabel = 'Skip',
  });

  final String question;
  final ValueChanged<String> onAnswer;
  final VoidCallback? onSkip;
  final String skipLabel;

  Widget _answer(String value, String label) {
    return Expanded(
      child: GestureDetector(
        key: ValueKey<String>('feeling-$value'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onAnswer(value),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: OG.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label, style: OG.body(size: 14, weight: FontWeight.w800)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ogBox(color: OG.accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(question, style: OG.body(size: 17, weight: FontWeight.w800, color: OG.white)),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _answer('fine', 'Fine'),
              const SizedBox(width: 8),
              _answer('noticed', 'Noticed it'),
              const SizedBox(width: 8),
              _answer('bad', 'Bad'),
            ],
          ),
          if (onSkip != null)
            GestureDetector(
              key: const ValueKey<String>('feeling-skip'),
              behavior: HitTestBehavior.opaque,
              onTap: onSkip,
              child: Container(
                height: 40,
                alignment: Alignment.centerLeft,
                child: Text(skipLabel, style: OG.body(size: 14, weight: FontWeight.w700, color: OG.white)),
              ),
            ),
        ],
      ),
    );
  }
}
