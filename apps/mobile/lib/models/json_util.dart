/// Tolerant JSON readers. Never throw on odd input; return a default instead.
library;

Map<String, dynamic> asMap(Object? v) {
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  return <String, dynamic>{};
}

List<Object?> asList(Object? v) {
  if (v is List) {
    return List<Object?>.from(v);
  }
  return <Object?>[];
}

String str(Object? v, [String fallback = '']) => v is String ? v : fallback;

String? strOrNull(Object? v) => v is String ? v : null;

int intOf(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

int? intOrNull(Object? v) => v is num ? v.toInt() : null;

double dblOf(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

double? dblOrNull(Object? v) => v is num ? v.toDouble() : null;

List<String> strList(Object? v) {
  final List<String> out = <String>[];
  for (final Object? e in asList(v)) {
    if (e is String) {
      out.add(e);
    }
  }
  return out;
}
