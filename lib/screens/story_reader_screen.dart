import 'package:flutter/material.dart';

import '../models/story_models.dart';
import 'story_reader_screen_enhanced.dart';

/// Thin wrapper so legacy navigation paths (e.g. Story Lab) automatically
/// receive the latest enhanced reader experience with the plush mic control.
class StoryReaderScreen extends StatelessWidget {
  final StoryChapter story;
  final String profileId;
  final String childName;

  const StoryReaderScreen({
    Key? key,
    required this.story,
    required this.profileId,
    required this.childName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StoryReaderScreenEnhanced(
      story: story,
      profileId: profileId,
      childName: childName,
    );
  }
}


