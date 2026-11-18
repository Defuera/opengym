/// Maps Convex documents to app models and back. Pure Dart.
///
/// Convex documents carry client-made ids under other names (`sessionId`,
/// `goalId`, `itemId`, `importId`). The models call them `id`.
library;

import '../models.dart';
import '../models/json_util.dart';
import 'convex_types.dart';

/// Deep copy with every map typed `Map<String, dynamic>`.
Object? normalize(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> e in v.entries) e.key.toString(): normalize(e.value),
    };
  }
  if (v is List) {
    return <dynamic>[for (final Object? e in v) normalize(e)];
  }
  return v;
}

Map<String, dynamic> _doc(Object? v, String idKey) {
  final Map<String, dynamic> m = asMap(normalize(v));
  m['id'] = m[idKey];
  return m;
}

List<T> _list<T>(Object? v, T Function(Object?) one) {
  return <T>[for (final Object? e in asList(v)) one(e)];
}

Session decodeSession(Object? v) => Session.fromJson(_doc(v, 'sessionId'));
List<Session> decodeSessions(Object? v) => _list(v, decodeSession);

Goal decodeGoal(Object? v) => Goal.fromJson(_doc(v, 'goalId'));
List<Goal> decodeGoals(Object? v) => _list(v, decodeGoal);

ContextItem decodeContextItem(Object? v) => ContextItem.fromJson(_doc(v, 'itemId'));
List<ContextItem> decodeContext(Object? v) => _list(v, decodeContextItem);

ImportJob decodeImport(Object? v) => ImportJob.fromJson(_doc(v, 'importId'));
List<ImportJob> decodeImports(Object? v) => _list(v, decodeImport);

Place decodePlace(Object? v) => Place.fromJson(asMap(normalize(v)));
List<Place> decodePlaces(Object? v) => _list(v, decodePlace);

Thread decodeThread(Object? v) => Thread.fromJson(_doc(v, 'threadId'));
List<Thread> decodeThreads(Object? v) => _list(v, decodeThread);

Message decodeMessage(Object? v) => Message.fromJson(_doc(v, 'messageId'));
List<Message> decodeMessages(Object? v) => _list(v, decodeMessage);

AiSettings decodeAiSettings(Object? v) => AiSettings.fromJson(asMap(normalize(v)));

/// The answer of `queries/sessions:load`: muscle key -> level, or null.
Map<String, int>? decodeSessionLoad(Object? v) {
  if (v == null) {
    return null;
  }
  final Map<String, dynamic> m = asMap(normalize(v));
  return <String, int>{
    for (final MapEntry<String, dynamic> e in m.entries)
      if (e.value is num) e.key: (e.value as num).toInt(),
  };
}

AboutMe decodeAboutMe(Object? v) => AboutMe.fromJson(normalize(v));
List<AskItem> decodeAskAfter(Object? v) => _list(v, (Object? e) => AskItem.fromJson(normalize(e)));

FileMeta decodeFileMeta(Object? v) => FileMeta.fromJson(_doc(v, 'fileId'));

/// The answer of `queries/files:get`: meta plus a URL, or null when unknown.
FileLink? decodeFileLink(Object? v) {
  if (v is! Map) {
    return null;
  }
  final Map<String, dynamic> m = asMap(normalize(v));
  return FileLink(decodeFileMeta(m), strOrNull(m['url']));
}

Stored<Plan> decodePlan(Object? v) {
  final Map<String, dynamic> m = asMap(normalize(v));
  final Plan p = Plan.fromJson(asMap(m['plan']));
  return Stored<Plan>(p, stored: m['stored'] == true, source: p.source);
}

/// The answer of `queries/start:request`: null, or the request state.
StartRequest? decodeStartRequest(Object? v) {
  return v is Map ? StartRequest.fromJson(asMap(normalize(v))) : null;
}

Stored<Dashboard> decodeDashboard(Object? v) {
  final Map<String, dynamic> m = asMap(normalize(v));
  final Dashboard d = Dashboard.fromJson(asMap(m['dashboard']));
  return Stored<Dashboard>(d, stored: m['stored'] == true, source: d.source);
}

/// The value is null when the session does not exist on the server yet.
Stored<Review?> decodeReview(Object? v) {
  final Map<String, dynamic> m = asMap(normalize(v));
  final Object? r = m['review'];
  final Review? review = r is Map ? Review.fromJson(asMap(r)) : null;
  return Stored<Review?>(
    review,
    stored: m['stored'] == true,
    source: review?.source ?? 'rules',
  );
}

/// Contract shape of a session, with the client-made id as `sessionId`.
Map<String, dynamic> encodeSession(Session s) {
  final Map<String, dynamic> m = s.toContractJson();
  m['sessionId'] = m.remove('id');
  return m;
}

LogEntry decodeEntry(Object? v) => LogEntry.fromJson(asMap(normalize(v)));
List<LogEntry> decodeEntries(Object? v) => _list(v, decodeEntry);
