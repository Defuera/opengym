import 'package:flutter/foundation.dart';

import '../models.dart';
import 'start_run.dart';

/// What the session screen shows about the coach's plan when the coach did
/// not answer in time: why the session is the app's own plan ([notice]) and
/// the coach's plan that came late ([offer]). Changing the session is done in
/// the chat (ADR-032).
class ProposalRebuild extends ChangeNotifier {
  ProposalRebuild({
    required this.onProposal,
    String? notice,
    StartRun? late,
  })  : _notice = notice,
        _late = late {
    late?.late.then((StartProposal p) {
      if (_disposed || _late != late || p.kind != 'gym') {
        return;
      }
      _offer = p;
      notifyListeners();
    });
  }

  /// Shows a new proposal. Returns false when it could not be shown (for
  /// example the session was already started): the rebuild then counts as failed.
  final bool Function(StartProposal) onProposal;

  String? _notice;
  StartRun? _late;
  StartProposal? _offer;
  bool _disposed = false;

  /// Why the shown session is not the coach's plan (the coach did not answer);
  /// null when it is, or after the coach's plan was taken.
  String? get notice => _notice;

  /// The coach's plan that came after the app gave up waiting. Null when there is none.
  StartProposal? get offer => _offer;

  /// Shows the late plan of the coach in place of the session. False when it could not be shown.
  bool useOffer() {
    final StartProposal? p = _offer;
    final StartRun? run = _late;
    if (p == null || run == null) {
      return false;
    }
    _offer = null;
    _late = null;
    final bool shown = onProposal(p);
    if (shown) {
      _notice = null;
    }
    notifyListeners();
    return shown;
  }

  @override
  void dispose() {
    _disposed = true;
    _late?.cancel();
    super.dispose();
  }
}
