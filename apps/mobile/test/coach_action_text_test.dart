import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/coach_action_text.dart';
import 'package:opengym/models.dart';

CoachAction _a(String name, String status, {String? reason}) =>
    CoachAction(actionId: 'x', name: name, status: status, reason: reason);

void main() {
  test('an applied function is one plain line by its name', () {
    expect(coachActionLine(_a('replace_open_exercise', 'applied')), 'Changed: one exercise');
    expect(coachActionLine(_a('add_open_exercise', 'applied')), 'Added: one exercise');
    expect(coachActionLine(_a('remove_open_exercise', 'applied')), 'Removed: one exercise');
    expect(coachActionLine(_a('rebuild_open_session', 'applied')), 'Rebuilt: the whole session');
    expect(coachActionLine(_a('update_place', 'applied')), 'Updated: place');
  });

  test('a rejected function says what the server said', () {
    expect(coachActionLine(_a('replace_open_exercise', 'rejected', reason: 'this exercise already has a done set')),
        'Not changed: this exercise already has a done set');
    expect(coachActionLine(_a('replace_open_exercise', 'rejected')), 'Not changed: one exercise');
  });

  test('an applied function with a note shows the note; a draft says draft; an unknown name is still a line', () {
    expect(coachActionLine(_a('update_place', 'applied', reason: 'no change: the place text says it already')),
        'No change: the place text says it already');
    expect(coachActionLine(_a('update_place', 'drafted')), 'Draft: place');
    expect(coachActionLine(_a('something_new', 'applied')), 'Changed: something');
  });

  test('a message decodes its context, actions and question', () {
    final Message m = Message.fromJson(<String, dynamic>{
      'id': 'm',
      'threadId': 't',
      'role': 'assistant',
      'text': 'Done.',
      'createdAt': 1,
      'turnId': 'u',
      'context': <String, dynamic>{'screen': 'exercise', 'openSessionId': 's', 'exerciseId': 'e'},
      'actions': <Map<String, dynamic>>[
        <String, dynamic>{'actionId': 'a1', 'name': 'update_place', 'status': 'applied'},
      ],
      'question': <String, dynamic>{
        'text': 'Which?',
        'answers': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'label': 'Gym'},
        ],
      },
    });
    expect(m.context!.screen, 'exercise');
    expect(m.context!.exerciseId, 'e');
    expect(m.actions.single.name, 'update_place');
    expect(m.question!.answers.single.label, 'Gym');
    expect(const ChatContext(screen: 'session', openSessionId: 's').toJson(),
        <String, dynamic>{'screen': 'session', 'openSessionId': 's'});
  });
}
