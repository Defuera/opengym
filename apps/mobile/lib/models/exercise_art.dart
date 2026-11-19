import 'json_util.dart';

/// The server's picture state for one exercise name (`queries/exerciseArt:get`).
/// [status] is none | pending | ready | failed. [url] is set only when ready.
/// The image holds two poses side by side: start on the left, end on the right.
class ExerciseArt {
  const ExerciseArt({required this.name, required this.status, this.url});

  final String name;
  final String status;
  final String? url;

  bool get ready => status == 'ready' && url != null && url!.isNotEmpty;

  /// Reads one item. Odd input never throws.
  factory ExerciseArt.fromJson(Map<String, dynamic> j) =>
      ExerciseArt(name: str(j['name']), status: str(j['status'], 'none'), url: strOrNull(j['url']));
}

/// The key the server uses: trimmed, lower case, white space runs made one space.
String exerciseArtKey(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
