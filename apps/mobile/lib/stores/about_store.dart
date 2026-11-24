import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/about_repository.dart';
import '../data/convex_client.dart';
import '../models.dart';
import '../planner.dart';

/// "How was the <limit> today?" for one finished session.
class AskPrompt {
  const AskPrompt({required this.sessionId, required this.item});

  final String sessionId;
  final AskItem item;
}

/// "About me": limits, body load and the after-session questions.
class AboutStore extends ChangeNotifier {
  AboutStore({required AboutRepository repo, this.askTimeout = const Duration(seconds: 8)})
      : _repo = repo;

  final AboutRepository _repo;
  final Duration askTimeout;

  AboutMe data = const AboutMe();
  bool loading = true;
  String? error;

  /// Open after-session questions, oldest first.
  List<AskPrompt> asks = <AskPrompt>[];
  StreamSubscription<AboutMe>? _sub;

  void start() {
    _sub ??= _repo.watch().listen(
      (AboutMe v) {
        data = v;
        loading = false;
        error = null;
        notifyListeners();
      },
      onError: (Object e) {
        loading = false;
        error = e is ConvexCallException ? e.message : 'Could not load About me.';
        notifyListeners();
      },
    );
  }

  Limit? limit(String id) => data.limitById(id);

  /// Names of the exercises the user knows: the ones of the log, once each.
  static List<String> knownExercises(Iterable<String> logged) {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final String n in logged) {
      if (n.trim().isNotEmpty && seen.add(n)) {
        out.add(n);
      }
    }
    return out;
  }

  // ---------- writes ----------

  Future<void> setStatus(Limit l, String status) => _repo.saveLimit(l.copyWith(status: status));

  Future<void> setRules(Limit l, List<LimitRule> rules) => _repo.saveLimit(l.copyWith(rules: rules));

  Future<void> removeLimit(String id) => _repo.removeLimit(id);

  Future<void> addRecord({
    required String limitId,
    required String title,
    required String text,
    String? date,
  }) =>
      _repo.addRecord(LimitRecord(id: newId(), limitId: limitId, title: title, text: text, date: date));

  Future<void> removeRecord(String id) => _repo.removeRecord(id);

  Future<void> checkin(String limitId, String feeling, {String? sessionId}) => _repo.saveCheckin(Checkin(
        id: newId(),
        limitId: limitId,
        at: DateTime.now().millisecondsSinceEpoch,
        feeling: feeling,
        sessionId: sessionId,
      ));

  // ---------- after a session ----------

  /// Asks the server which limits [sessionId] loaded and queues one question
  /// for each. Never throws and never blocks saving: offline or a failing
  /// query means no question.
  Future<void> askAfter(String sessionId) async {
    try {
      final List<AskItem> items = await _repo.askAfter(sessionId).timeout(askTimeout);
      final List<AskPrompt> add = <AskPrompt>[
        for (final AskItem i in items)
          if (!asks.any((AskPrompt a) => a.sessionId == sessionId && a.item.limitId == i.limitId))
            AskPrompt(sessionId: sessionId, item: i),
      ];
      if (add.isNotEmpty) {
        asks = <AskPrompt>[...asks, ...add];
        notifyListeners();
      }
    } catch (_) {
      // A bonus question: skip silently.
    }
  }

  Future<void> answerAsk(AskPrompt p, String feeling) async {
    _drop(p);
    try {
      await checkin(p.item.limitId, feeling, sessionId: p.sessionId);
    } catch (_) {
      // The outbox keeps writes; nothing to show here.
    }
  }

  void skipAsk(AskPrompt p) => _drop(p);

  void _drop(AskPrompt p) {
    asks = <AskPrompt>[for (final AskPrompt a in asks) if (a != p) a];
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
