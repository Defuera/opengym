import 'package:flutter/material.dart';

import '../theme.dart';
import 'status_pill.dart';

/// One limit in the Limits list: title, first rules, status and the recent
/// check-ins as small bars (oldest left; dark = bad, grey = noticed it,
/// light = fine). [feelings] holds fine | noticed | bad, oldest first.
class LimitCard extends StatelessWidget {
  const LimitCard({
    super.key,
    required this.title,
    required this.summary,
    required this.status,
    required this.statusLabel,
    required this.feelings,
    required this.onTap,
  });

  final String title;
  final String summary;
  final String status;
  final String statusLabel;
  final List<String> feelings;
  final VoidCallback onTap;

  Color _dot(String f) => f == 'bad'
      ? OG.ink
      : f == 'noticed'
          ? const Color(0xFF8C8A84)
          : OG.soft;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: ogBox(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: OG.display(19)),
                  if (summary.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: OG.muted(size: 13, weight: FontWeight.w500),
                    ),
                  ],
                  if (feelings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        for (final String f in feelings)
                          Container(
                            width: 14,
                            height: 8,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: _dot(f),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusPill(label: statusLabel, status: status),
          ],
        ),
      ),
    );
  }
}
