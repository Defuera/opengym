import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/cta_button.dart';
import '../widgets/exercise_card.dart';
import '../widgets/exercise_panel.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/item_state.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/plus_bar.dart';
import '../widgets/prediction_card.dart';
import '../widgets/session_list_item.dart';
import '../widgets/set_tile.dart';
import '../widgets/stat_tile.dart';
import '../widgets/stepper_row.dart';

void _noop() {}

const SizedBox _gap = SizedBox(height: 12);

Widget buttonsStory(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      OgButton(onPressed: _noop, child: const Text('Plain')),
      _gap,
      OgButton(
        variant: OgVariant.accent,
        onPressed: _noop,
        child: const Text('Accent'),
      ),
      _gap,
      OgButton(
        variant: OgVariant.ink,
        onPressed: _noop,
        child: const Text('Ink'),
      ),
      _gap,
      OgButton(
        variant: OgVariant.dashed,
        onPressed: _noop,
        child: const Text('Dashed soft'),
      ),
      _gap,
      const OgButton(onPressed: null, child: Text('Disabled')),
      _gap,
      const Row(children: <Widget>[
        OgIconButton(icon: Icons.close, onPressed: _noop),
        SizedBox(width: 12),
        OgIconButton(icon: Icons.chevron_left, onPressed: _noop),
      ]),
    ],
  );
}

Widget ctaStory(BuildContext context) {
  return Column(
    children: <Widget>[
      CtaButton(
        label: 'Complete set',
        icon: Icons.check,
        variant: OgVariant.accent,
        onPressed: _noop,
      ),
      _gap,
      CtaButton(
        label: 'Next exercise',
        icon: Icons.arrow_forward,
        iconAfter: true,
        onPressed: _noop,
      ),
      _gap,
      CtaButton(label: 'Finish session', icon: Icons.check, onPressed: _noop),
    ],
  );
}

Widget statTilesStory(BuildContext context) {
  return const Row(
    children: <Widget>[
      Expanded(child: StatTile(label: 'Sessions', value: '3')),
      SizedBox(width: 12),
      Expanded(
        child: StatTile(
          label: 'Bench press top set',
          value: '60 kg',
          highlighted: true,
        ),
      ),
    ],
  );
}

Widget listItemsStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      SessionListItem(
        title: 'Gym · Push',
        subtitle: 'Today',
        trailing: '12 sets',
      ),
      SizedBox(height: 10),
      SessionListItem(title: 'Run', subtitle: 'Yesterday', trailing: '30 min'),
    ],
  );
}

Widget _fixed(Widget w) => SizedBox(height: 122, child: w);

Widget exerciseCardsStory(BuildContext context) {
  return Wrap(
    spacing: 10,
    runSpacing: 14,
    children: <Widget>[
      _fixed(ExerciseCard(
        name: 'Bench press',
        progressLabel: '2 / 4 sets',
        state: ItemState.current,
        onTap: _noop,
        onMoveEarlier: _noop,
        onDiscard: _noop,
      )),
      _fixed(ExerciseCard(
        name: 'Overhead press',
        progressLabel: 'Done',
        state: ItemState.finished,
        onTap: _noop,
        onMoveEarlier: _noop,
        onDiscard: _noop,
      )),
      _fixed(ExerciseCard(
        name: 'Dips',
        progressLabel: '0 / 3 sets',
        canMoveEarlier: false,
        onTap: _noop,
        onDiscard: _noop,
      )),
      _fixed(AddCard(onTap: _noop)),
    ],
  );
}

Widget setTilesStory(BuildContext context) {
  return const SetGrid(
    children: <Widget>[
      SetTile(label: 'Set 1', value: '6×20', state: ItemState.finished, checked: true),
      SetTile(label: 'Set 2', value: '6×40', state: ItemState.current),
      SetTile(label: 'Set 3', value: '6×60'),
      SetTile(label: 'Max', value: '1×60'),
      ToolTile(label: '+ Set', onTap: _noop),
      ToolTile(label: '− Set', onTap: _noop),
    ],
  );
}

Widget panelStory(BuildContext context) {
  return SizedBox(
    height: 470,
    child: ExercisePanel(
      name: 'Bench press',
      hint: 'First time here. Set your numbers once; next time they are pre-filled.',
      onSwap: _noop,
      children: <Widget>[
        const SetGrid(children: <Widget>[
          SetTile(label: 'Set 1', value: '6×20', state: ItemState.current),
          SetTile(label: 'Set 2', value: '6×40'),
          ToolTile(label: '+ Set', onTap: _noop),
        ]),
        StepperRow(label: 'Set 1 · Reps', value: '6', onMinus: _noop, onPlus: _noop),
        StepperRow(label: 'Weight (kg)', value: '20', onMinus: _noop, onPlus: _noop),
      ],
    ),
  );
}

Widget choiceCardsStory(BuildContext context) {
  return Column(
    children: <Widget>[
      const PredictionCard(
        rankLabel: '1 · Most likely',
        title: 'Gym · Push',
        subtitle: 'Session ready to follow',
        onTap: _noop,
      ),
      _gap,
      const OptionGrid(children: <Widget>[
        OptionCard(
          number: '2',
          title: 'Gym · Pull',
          subtitle: 'Last done 3 days ago',
          onTap: _noop,
        ),
        OptionCard(number: '3', title: 'Other activity', onTap: _noop),
        OptionCard(
          icon: Icons.add,
          title: 'Empty gym session',
          dashed: true,
          onTap: _noop,
        ),
      ]),
    ],
  );
}

Widget notesStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      NoteBox(
        title: 'Nothing logged yet.',
        message: 'Press the plus button to start your first session.',
      ),
      SizedBox(height: 12),
      SizedBox(
        height: 140,
        child: NoteBox(
          title: 'No exercises yet.',
          message: 'Add one from the row above.',
          centered: true,
        ),
      ),
    ],
  );
}

Widget plusBarStory(BuildContext context) {
  return const PlusBar(onPressed: _noop);
}

Widget sheetsStory(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      OgButton(
        onPressed: () {
          showChoiceSheet(
            context,
            title: 'End this session?',
            choices: const <SheetChoice>[
              SheetChoice(
                value: 'a',
                label: 'Finish and save',
                variant: OgVariant.accent,
              ),
              SheetChoice(value: 'b', label: 'Discard without saving'),
              SheetChoice(
                value: 'c',
                label: 'Keep going',
                variant: OgVariant.dashed,
              ),
            ],
          );
        },
        child: const Text('Open choice sheet'),
      ),
      _gap,
      OgButton(
        onPressed: () {
          showExercisePicker(
            context,
            title: 'Add exercise',
            options: const <String>['Bench press', 'Dips', 'Squat', 'Plank'],
          );
        },
        child: Text('Open exercise picker', style: OG.body(weight: FontWeight.w700)),
      ),
    ],
  );
}
