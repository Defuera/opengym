import 'package:flutter/material.dart';

import '../models.dart';
import '../stores/ai_model_store.dart';
import '../stores/connection_store.dart';
import '../widgets/coach_model_section.dart';

/// Connects the "Coach model" block of Settings to its store and the link state.
class CoachModelPanel extends StatelessWidget {
  const CoachModelPanel({super.key, required this.store, required this.connection});

  final AiModelStore store;
  final ConnectionStore connection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[store, connection]),
      builder: (BuildContext context, Widget? child) {
        final AiSettings? s = store.settings;
        return CoachModelSection(
          provider: s?.provider ?? 'none',
          effective: store.effective,
          defaultModel: s?.defaultModel,
          selected: store.selected,
          models: s?.models ?? const <String>[],
          fetchedAt: s?.fetchedAt,
          error: store.error ?? s?.error,
          refreshing: store.refreshing,
          enabled: connection.connected && s != null,
          onPick: store.pick,
          onRefresh: store.refresh,
        );
      },
    );
  }
}
