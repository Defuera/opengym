import 'package:flutter/material.dart';

import '../theme.dart';
import 'labeled_field.dart';
import 'og_button.dart';
import 'section_header.dart';
import 'status_line.dart';

/// The "Coach model" block of Settings. Standalone: it holds only what it shows
/// and reports taps through callbacks.
class CoachModelSection extends StatefulWidget {
  const CoachModelSection({
    super.key,
    required this.provider,
    required this.effective,
    required this.defaultModel,
    required this.selected,
    required this.models,
    required this.fetchedAt,
    required this.onPick,
    required this.onRefresh,
    this.enabled = true,
    this.refreshing = false,
    this.error,
  });

  final String provider;

  /// The model in use. Null: none is set.
  final String? effective;
  final String? defaultModel;

  /// The model the owner chose. Null: the default is in use.
  final String? selected;
  final List<String> models;
  final DateTime? fetchedAt;

  /// A model id, or null for the default.
  final ValueChanged<String?> onPick;
  final VoidCallback onRefresh;

  /// False when offline: every control is off.
  final bool enabled;
  final bool refreshing;
  final String? error;

  static const Key customFieldKey = Key('coach-model-custom');
  static const Key useKey = Key('coach-model-use');
  static const Key refreshKey = Key('coach-model-refresh');
  static const Key defaultRowKey = Key('coach-model-default');
  static Key rowKey(String id) => Key('coach-model-row-$id');

  static final RegExp _validId = RegExp(r'^[A-Za-z0-9._:-]{1,100}$');
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  /// "17 Nov, 20:50"
  static String stamp(DateTime t) =>
      '${t.day} ${_months[t.month - 1]}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  State<CoachModelSection> createState() => _CoachModelSectionState();
}

class _CoachModelSectionState extends State<CoachModelSection> {
  final TextEditingController _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String get _typed => _custom.text.trim();
  bool get _canUse => widget.enabled && CoachModelSection._validId.hasMatch(_typed);

  void _use() {
    widget.onPick(_typed);
    setState(_custom.clear);
  }

  @override
  Widget build(BuildContext context) {
    final String? def = widget.defaultModel;
    // A chosen id that is not in the list still needs a row, or it would not show as selected.
    final List<String> ids = <String>[
      if (widget.selected != null && !widget.models.contains(widget.selected)) widget.selected!,
      ...widget.models,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionHeader(title: 'Coach model'),
        const SizedBox(height: 8),
        _summary(def),
        if (!widget.enabled) ...<Widget>[
          const SizedBox(height: 12),
          const StatusLine(text: 'Offline: connect to change the coach model.', connected: false),
        ],
        const SizedBox(height: 14),
        _list(def, ids),
        const SizedBox(height: 14),
        _refreshRow(),
        if (widget.error != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(widget.error!, style: OG.muted(size: 14)),
        ],
        const SizedBox(height: 14),
        LabeledField(
          key: CoachModelSection.customFieldKey,
          label: 'Other model id',
          controller: _custom,
          hint: 'For a model that is not in the list',
          helper: 'Letters, digits and . _ : - only.',
          maxLength: 100,
          readOnly: !widget.enabled,
          onChanged: (String _) => setState(() {}),
          onSubmitted: (String _) {
            if (_canUse) {
              _use();
            }
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OgButton(
            key: CoachModelSection.useKey,
            onPressed: _canUse ? _use : null,
            minHeight: 48,
            child: const Text('Use'),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Applies to plans, advice, reviews and chat from the next request. '
          'If the provider refuses the model, the app falls back to plain rules.',
          style: OG.muted(size: 14),
        ),
      ],
    );
  }

  Widget _summary(String? def) {
    final bool chosen = widget.selected != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.effective ?? 'No model set', style: OG.display(26)),
          const SizedBox(height: 6),
          Text('Provider: ${widget.provider}', style: OG.muted(size: 15)),
          if (chosen && def != null) Text('Default: $def', style: OG.muted(size: 15)),
        ],
      ),
    );
  }

  Widget _list(String? def, List<String> ids) {
    final bool noList = widget.models.isEmpty;
    return Container(
      decoration: ogBox(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 336),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: <Widget>[
            _row(CoachModelSection.defaultRowKey, def == null ? 'Default' : 'Default ($def)', widget.selected == null, null),
            for (final String id in ids) ...<Widget>[
              const Divider(height: 1, thickness: 1.5, color: OG.soft),
              _row(CoachModelSection.rowKey(id), id, widget.selected == id, id),
            ],
            if (noList) ...<Widget>[
              const Divider(height: 1, thickness: 1.5, color: OG.soft),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Press Refresh list to load the models your provider offers.',
                  style: OG.muted(size: 15),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Key key, String label, bool on, String? id) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? () => widget.onPick(id) : null,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.35,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: OG.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: OG.ink, width: OG.borderWidth),
                ),
                child: on
                    ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: OG.accent, shape: BoxShape.circle))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: OG.body(weight: on ? FontWeight.w700 : FontWeight.w400))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _refreshRow() {
    final DateTime? at = widget.fetchedAt;
    return Row(
      children: <Widget>[
        OgButton(
          key: CoachModelSection.refreshKey,
          onPressed: widget.enabled && !widget.refreshing ? widget.onRefresh : null,
          minHeight: 48,
          child: Text(widget.refreshing ? 'Refreshing…' : 'Refresh list'),
        ),
        const SizedBox(width: 14),
        if (at != null) Expanded(child: Text('Updated ${CoachModelSection.stamp(at)}', style: OG.muted(size: 14))),
      ],
    );
  }
}
