import 'package:flutter/material.dart';

import 'story_builders.dart';
import 'story_stateful.dart';

/// One entry per widget section. Adding a story is one entry here.
class GalleryStory {
  const GalleryStory({required this.title, required this.builder});

  final String title;
  final WidgetBuilder builder;
}

final List<GalleryStory> galleryStories = <GalleryStory>[
  const GalleryStory(title: 'OgButton and OgIconButton', builder: buttonsStory),
  const GalleryStory(title: 'CtaButton', builder: ctaStory),
  GalleryStory(title: 'StepperRow (counts)', builder: (BuildContext c) => const StepperDemo()),
  const GalleryStory(title: 'StatTile', builder: statTilesStory),
  GalleryStory(title: 'SegmentedToggle', builder: (BuildContext c) => const ToggleDemo()),
  const GalleryStory(title: 'SessionListItem', builder: listItemsStory),
  const GalleryStory(title: 'ExerciseCard and AddCard', builder: exerciseCardsStory),
  GalleryStory(title: 'ExerciseCarousel', builder: (BuildContext c) => const CarouselDemo()),
  const GalleryStory(title: 'SetTile, ToolTile, SetGrid', builder: setTilesStory),
  const GalleryStory(title: 'ExercisePanel', builder: panelStory),
  const GalleryStory(title: 'PredictionCard and OptionCard', builder: choiceCardsStory),
  GalleryStory(title: 'OgChip', builder: (BuildContext c) => const ChipsDemo()),
  const GalleryStory(title: 'NoteBox', builder: notesStory),
  const GalleryStory(title: 'PlusBar', builder: plusBarStory),
  const GalleryStory(title: 'Sheets', builder: sheetsStory),
];
