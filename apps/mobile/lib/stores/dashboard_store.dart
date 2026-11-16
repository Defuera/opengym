import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../models.dart';

/// GET /v1/dashboard for the selected period. Keeps the last good result.
class DashboardStore extends ChangeNotifier {
  DashboardStore({required OpenGymApi api}) : _api = api;

  final OpenGymApi _api;

  Dashboard? dashboard;
  int days = 7;
  bool loading = false;
  String? error;
  int _gen = 0;

  Future<void> load(int period) async {
    days = period;
    await refresh();
  }

  Future<void> refresh() async {
    final int gen = ++_gen;
    loading = true;
    notifyListeners();
    Dashboard? got;
    String? err;
    try {
      got = await _api.dashboard(days);
    } on ApiException catch (e) {
      err = e.message;
    } catch (_) {
      err = 'Could not load the dashboard.';
    }
    if (gen != _gen) {
      return;
    }
    loading = false;
    error = err;
    if (got != null) {
      dashboard = got;
    }
    notifyListeners();
  }

  /// The dashboard that matches the selected period, if one is loaded.
  Dashboard? get current {
    final Dashboard? d = dashboard;
    return (d != null && d.days == days) ? d : null;
  }
}
