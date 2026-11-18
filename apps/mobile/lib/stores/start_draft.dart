import 'package:flutter/widgets.dart';

/// The steps of the Start tab: the list of types, the "Other" form, the details.
enum StartStep { types, other, details }

/// What the Start tab holds between tab switches: the step, the chosen type,
/// the note for today and the text typed under "Other". Owned by the plus
/// sheet; the Start tab only reads it.
class StartDraft extends ChangeNotifier {
  /// The optional note for today (max 200).
  final TextEditingController note = TextEditingController();

  /// What the user wants to do, typed under "Other" (max 200).
  final TextEditingController otherText = TextEditingController();
  StartStep _step = StartStep.types;
  String _type = '';

  StartStep get step => _step;

  /// The type of step 2 (a name from the log).
  String get type => _type;

  void openOther() {
    _step = StartStep.other;
    notifyListeners();
  }

  /// Step 2 for [name], a type with sets.
  void pick(String name) {
    _type = name;
    _step = StartStep.details;
    notifyListeners();
  }

  /// Back to the list of types. Typed values stay.
  void back() {
    _step = StartStep.types;
    notifyListeners();
  }

  @override
  void dispose() {
    note.dispose();
    otherText.dispose();
    super.dispose();
  }
}
