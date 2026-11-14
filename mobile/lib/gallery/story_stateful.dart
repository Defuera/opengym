import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/exercise_card.dart';
import '../widgets/exercise_carousel.dart';
import '../widgets/item_state.dart';
import '../widgets/og_chip.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/stepper_row.dart';

/// Stepper that really counts.
class StepperDemo extends StatefulWidget {
  const StepperDemo({super.key});

  @override
  State<StepperDemo> createState() => _StepperDemoState();
}

class _StepperDemoState extends State<StepperDemo> {
  double _kg = 60;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ogBox(radius: 20),
      child: StepperRow(
        label: 'Weight (kg)',
        value: _kg == _kg.truncateToDouble() ? '${_kg.toInt()}' : '$_kg',
        onMinus: () => setState(() => _kg = _kg - 2.5 < 0 ? 0 : _kg - 2.5),
        onPlus: () => setState(() => _kg = _kg + 2.5),
      ),
    );
  }
}

class ToggleDemo extends StatefulWidget {
  const ToggleDemo({super.key});

  @override
  State<ToggleDemo> createState() => _ToggleDemoState();
}

class _ToggleDemoState extends State<ToggleDemo> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return SegmentedToggle(
      labels: const <String>['Last week', 'Last month'],
      selectedIndex: _i,
      onChanged: (int i) => setState(() => _i = i),
    );
  }
}

class ChipsDemo extends StatefulWidget {
  const ChipsDemo({super.key});

  @override
  State<ChipsDemo> createState() => _ChipsDemoState();
}

class _ChipsDemoState extends State<ChipsDemo> {
  String _sel = 'Run';

  @override
  Widget build(BuildContext context) {
    const List<String> names = <String>['Run', 'Walk', 'Cycle', 'Swim', 'Other'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String n in names)
          OgChip(label: n, selected: _sel == n, onTap: () => setState(() => _sel = n)),
      ],
    );
  }
}

/// Carousel with tappable cards and an Add card that appends one.
class CarouselDemo extends StatefulWidget {
  const CarouselDemo({super.key});

  @override
  State<CarouselDemo> createState() => _CarouselDemoState();
}

class _CarouselDemoState extends State<CarouselDemo> {
  final List<String> _names = <String>[
    'Bench press',
    'Overhead press',
    'Dips',
    'Triceps pushdown',
  ];
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[];
    for (int i = 0; i < _names.length; i++) {
      cards.add(ExerciseCard(
        name: _names[i],
        progressLabel: i == 0 ? 'Done' : '0 / 3 sets',
        state: i == _sel
            ? ItemState.current
            : (i == 0 ? ItemState.finished : ItemState.idle),
        canMoveEarlier: i > 0,
        onTap: () => setState(() => _sel = i),
        onMoveEarlier: () {},
        onDiscard: () {},
      ));
    }
    cards.add(AddCard(
      onTap: () => setState(() => _names.add('Exercise ${_names.length + 1}')),
    ));
    return ExerciseCarousel(children: cards, selectedIndex: _sel);
  }
}
