import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';

/// The dashboard for the selected period (7 or 30 days), as a live
/// subscription. Keeps the last good result while the other period loads.
class DashboardStore extends ChangeNotifier {
  DashboardStore({required ConvexClient client}) : _client = client;

  final ConvexClient _client;

  Dashboard? dashboard;
  int days = 7;
  bool loading = false;
  String? error;
  StreamSubscription<Stored<Dashboard>>? _sub;

  /// Follow the dashboard of [period]. Every server change is pushed.
  void select(int period) {
    if (_sub != null && period == days) {
      return;
    }
    days = period;
    loading = true;
    error = null;
    _sub?.cancel();
    _sub = _client.watchDashboard(period).listen(
      (Stored<Dashboard> r) {
        dashboard = r.value;
        loading = false;
        error = null;
        notifyListeners();
      },
      onError: (Object e) {
        loading = false;
        error = e is ConvexCallException ? e.message : 'Could not load the dashboard.';
        notifyListeners();
      },
    );
    notifyListeners();
  }

  /// The dashboard that matches the selected period, if one is loaded.
  Dashboard? get current {
    final Dashboard? d = dashboard;
    return (d != null && d.days == days) ? d : null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
