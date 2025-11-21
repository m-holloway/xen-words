import '../models/story_generation_models.dart';
import '../models/story_models.dart';

/// Built-in  entries that are always available and read-only.
class BuiltInStoryLibrary {
  static List<GeneratedStoryRecord> loadStories() {
    return [
      _sparkTrailAdventure,
      _moonlitGardenMystery,
    ];
  }

  static GeneratedStoryRecord get _sparkTrailAdventure {
    final beats = [
      StoryBeat(
        id: 'spark_beat_1',
        type: BeatType.narration,
        speaker: Speaker.parent,
        text: 'One cloudy afternoon you spot a ribbon of light sliding past the door. '
            'It wiggles like it is inviting you on a treasure hunt!',
      ),
      StoryBeat(
        id: 'spark_beat_2',
        type: BeatType.childTurn,
        speaker: Speaker.coach,
        text: 'Can you say the word "go"?',
        targetWords: const ['go'],
        coachPhrase: 'Ready, set, go!',
      ),
      StoryBeat(
        id: 'spark_beat_3',
        type: BeatType.narration,
        speaker: Speaker.parent,
        text: 'You lace up your rainbow boots and follow the glowing ribbon down the garden path.',
      ),
      StoryBeat(
        id: 'spark_beat_4',
        type: BeatType.childTurn,
        speaker: Speaker.coach,
        text: 'Point to the glowing ribbon and say "see".',
        targetWords: const ['see'],
        coachPhrase: 'Nice spotting!',
      ),
      StoryBeat(
        id: 'spark_beat_5',
        type: BeatType.narration,
        speaker: Speaker.parent,
        text: 'Suddenly, the ribbon splits! One path hums, the other whistles.',
      ),
      StoryBeat(
        id: 'spark_beat_6',
        type: BeatType.coachIntervention,
        speaker: Speaker.coach,
        text: 'This word is "what". Listen: WH-AT. Try it with me!',
        targetWords: const ['what'],
      ),
      StoryBeat(
        id: 'spark_beat_7',
        type: BeatType.celebration,
        speaker: Speaker.parent,
        text: 'You chose the humming path with confidence. The ribbon rewards you with a shower of sparks!',
      ),
    ];

    final chapter = StoryChapter(
      id: 'built_in_spark_trail',
      title: 'Spark Trail Adventure',
      beats: beats,
      choicePoints: const [],
      metadata: const {
        'built_in': true,
        'theme': 'adventure',
      },
    );

    return GeneratedStoryRecord(
      id: 'built_in_spark_trail',
      chapter: chapter,
      summary: 'Follow a glowing ribbon through the backyard to discover sparkly surprises '
          'while practicing confident sight words.',
      readingLevel: 2,
      durationMinutes: 6,
      focusWords: const ['go', 'see', 'what'],
      familiarWordRatio: 0.65,
      familiarWordCount: 39,
      totalWordCount: 60,
      parentPrompt: 'Built-in bedtime adventure',
      childContext: 'Encourage curiosity and perseverance',
      storyConcept: 'Chasing ribbon of light',
      model: 'built_in',
      includeChildName: false,
      createdAt: DateTime(2024, 1, 1),
      requestInputs: const {'built_in': true},
      isBuiltIn: true,
    );
  }

  static GeneratedStoryRecord get _moonlitGardenMystery {
    final beats = [
      StoryBeat(
        id: 'moon_beat_1',
        type: BeatType.narration,
        speaker: Speaker.parent,
        text: 'At bedtime a moonbeam lands on your pillow and whispers, '
            '"Come see the glowing garden!"',
      ),
      StoryBeat(
        id: 'moon_beat_2',
        type: BeatType.childTurn,
        speaker: Speaker.coach,
        text: 'Say the word "you" to show you are ready.',
        targetWords: const ['you'],
        coachPhrase: 'Yes, you are brave!',
      ),
      StoryBeat(
        id: 'moon_beat_3',
        type: BeatType.narration,
        speaker: Speaker.parent,
        text: 'You tiptoe outside and every flower lights up when you get close.',
      ),
      StoryBeat(
        id: 'moon_beat_4',
        type: BeatType.childTurn,
        speaker: Speaker.coach,
        text: 'Touch the brightest flower and say "see".',
        targetWords: const ['see'],
      ),
      StoryBeat(
        id: 'moon_beat_5',
        type: BeatType.narration,
        speaker: Speaker.parent,
        text: 'In the middle of the garden stands a shy fox holding a jar of stars.',
      ),
      StoryBeat(
        id: 'moon_beat_6',
        type: BeatType.childTurn,
        speaker: Speaker.coach,
        text: 'Whisper the word "glow" to help the fox.',
        targetWords: const ['glow'],
        coachPhrase: 'Glow like the moon!',
      ),
      StoryBeat(
        id: 'moon_beat_7',
        type: BeatType.celebration,
        speaker: Speaker.parent,
        text: 'The jar opens and thousands of tiny lights dance around you both. '
            'You solved the moonlit mystery!',
      ),
    ];

    final chapter = StoryChapter(
      id: 'built_in_moonlit_garden',
      title: 'Moonlit Garden Mystery',
      beats: beats,
      metadata: const {
        'built_in': true,
        'theme': 'calming',
      },
    );

    return GeneratedStoryRecord(
      id: 'built_in_moonlit_garden',
      chapter: chapter,
      summary: 'A moonbeam leads your child through a glowing garden where gentle prompts turn into sight-word wins.',
      readingLevel: 1,
      durationMinutes: 5,
      focusWords: const ['you', 'see', 'glow'],
      familiarWordRatio: 0.72,
      familiarWordCount: 41,
      totalWordCount: 57,
      parentPrompt: 'Calming moonlight walk',
      childContext: 'Wind-down routine',
      storyConcept: 'Helping a shy fox release light',
      model: 'built_in',
      includeChildName: false,
      createdAt: DateTime(2024, 1, 2),
      requestInputs: const {'built_in': true},
      isBuiltIn: true,
    );
  }
}


