import '../models/story_generation_models.dart';
import '../models/story_models.dart';

class StoryTextUtils {
  const StoryTextUtils._();

  static String narrationOnly(StoryChapter chapter) {
    final buffer = StringBuffer();
    for (final beat in chapter.beats) {
      if (beat.type != BeatType.narration) continue;
      final text = beat.text.trim();
      if (text.isEmpty) continue;
      buffer.writeln(text);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static String shareableStoryText(GeneratedStoryRecord story) {
    final buffer = StringBuffer();
    final title = story.chapter.title.trim();
    if (title.isNotEmpty) {
      buffer.writeln(title);
      buffer.writeln();
    }
    final narration = narrationOnly(story.chapter);
    if (narration.isNotEmpty) {
      buffer.writeln(narration);
    }
    return buffer.toString().trim();
  }
}

