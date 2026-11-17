import 'package:flutter/material.dart';

import 'story_builders.dart';
import 'story_net.dart';
import 'story_net_stateful.dart';
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
  const GalleryStory(title: 'SetRow and AddSetRow', builder: setRowsStory),
  const GalleryStory(title: 'ExercisePanel', builder: panelStory),
  const GalleryStory(title: 'PredictionCard and OptionCard', builder: choiceCardsStory),
  GalleryStory(title: 'OgChip', builder: (BuildContext c) => const ChipsDemo()),
  const GalleryStory(title: 'NoteBox', builder: notesStory),
  const GalleryStory(title: 'PlusBar', builder: plusBarStory),
  const GalleryStory(title: 'Sheets', builder: sheetsStory),
  const GalleryStory(title: 'ProgressBar', builder: progressStory),
  const GalleryStory(title: 'StatusLine', builder: statusStory),
  GalleryStory(title: 'LabeledField', builder: (BuildContext c) => const FieldDemo()),
  const GalleryStory(title: 'GoalProgressCard', builder: goalCardStory),
  const GalleryStory(title: 'TrendCard', builder: trendStory),
  const GalleryStory(title: 'ConsistencyRow', builder: consistencyStory),
  const GalleryStory(title: 'NoteCard', builder: noteCardStory),
  const GalleryStory(title: 'ReviewCard', builder: reviewStory),
  const GalleryStory(title: 'ChatBubble and SavedChips', builder: chatStory),
  const GalleryStory(title: 'AttachmentChip', builder: attachmentStory),
  GalleryStory(title: 'ComposerBar', builder: (BuildContext c) => const ComposerDemo()),
  const GalleryStory(title: 'ThreadCard', builder: threadCardStory),
  GalleryStory(title: 'ChipStrip', builder: (BuildContext c) => const ChipStripDemo()),
  const GalleryStory(title: 'NavBar', builder: navBarStory),
  const GalleryStory(title: 'GoalRow', builder: goalRowStory),
  const GalleryStory(title: 'ImportJobCard', builder: importStory),
  const GalleryStory(title: 'PreparingCard', builder: preparingStory),
  const GalleryStory(title: 'Text sheet', builder: textSheetStory),
];
