import 'json_util.dart';

/// A place the person trains at. [text] is what the coach knows about it
/// (free text, may be empty). The coach keeps it up to date; the app only
/// reads it.
class Place {
  const Place({required this.id, required this.name, this.text = '', this.updatedAt = 0});

  final String id;
  final String name;
  final String text;
  final int updatedAt;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'placeId': id, 'name': name, 'text': text, 'updatedAt': updatedAt};

  /// Reads a place (`queries/places:list`). Odd input never throws.
  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: str(j['placeId']),
        name: str(j['name']),
        text: str(j['text']),
        updatedAt: intOf(j['updatedAt']),
      );
}

/// The place of a coach proposal: just its id and name.
class PlaceRef {
  const PlaceRef({required this.id, required this.name});

  final String id;
  final String name;

  /// Null when the data holds no usable place.
  static PlaceRef? tryParse(Object? v) {
    final Map<String, dynamic> m = asMap(v);
    final String id = str(m['placeId']);
    return id.isEmpty ? null : PlaceRef(id: id, name: str(m['name']));
  }
}
