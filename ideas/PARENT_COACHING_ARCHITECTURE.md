# Parent-Child Coaching Sessions: Technical Architecture

## 🏗️ System Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────┐
│                  Parent Dashboard                    │
│  [Launch Coaching Session] ← Entry point           │
└───────────────────┬─────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────┐
│            Coaching Session Controller               │
│  • Session type selection (Victory/Challenge/Story) │
│  • Word selection (mastery-based)                   │
│  • Story template loading                           │
│  • Progress tracking                                │
└───────┬───────────────┬─────────────────┬──────────┘
        │               │                 │
    ┌───▼───┐      ┌───▼───┐        ┌───▼────┐
    │Story  │      │Speech │        │Coach   │
    │Reader │      │Engine │        │Persona │
    └───┬───┘      └───┬───┘        └───┬────┘
        │              │                │
        └──────────────┴────────────────┘
                       │
              ┌────────▼────────┐
              │   UI Layer      │
              │ • Bubbles       │
              │ • Highlighting  │
              │ • Animations    │
              └─────────────────┘
```

---

## 📦 Data Models

### CoachingSession

```dart
class CoachingSession {
  final String id;
  final SessionType type; // victory, challenge, story
  final String childProfileId;
  final List<String> targetWords;
  final String storyTemplate;
  final DateTime startTime;
  final List<WordAttempt> attempts;
  final int celebrationCount;
  final Duration duration;
  
  // Difficulty distribution
  final int easyWords; // 80%+ mastery
  final int mediumWords; // 50-79% mastery
  final int hardWords; // <50% mastery
}

enum SessionType {
  victoryLap,     // 5 min, mastered words only
  growthChallenge, // 10 min, mix of easy/hard
  storyAdventure,  // 15-20 min, full narrative
}
```

### StoryTemplate

```dart
class StoryTemplate {
  final String id;
  final String title;
  final List<StoryBeat> beats;
  final Map<String, String> illustrations; // beat_id -> image_path
  final String theme; // forest, space, ocean, etc.
  final int recommendedAge;
  
  // Word insertion points
  final List<WordSlot> wordSlots;
}

class StoryBeat {
  final String id;
  final String parentText; // What parent reads
  final BeatType type; // narration, child_prompt, coaching, celebration
  final String? coachPhrase; // If coaching moment
  final String? illustration;
}

enum BeatType {
  parentNarration,  // Parent reads, no interaction
  childPrompt,      // Child says word
  coachIntervention, // Coach helps with hard word
  celebrationMoment, // High-five, animation
}

class WordSlot {
  final int beatIndex; // Which story beat
  final int wordPosition; // Position in text
  final DifficultyLevel difficulty;
  final bool requiresCoaching; // Hard words get intervention
}

enum DifficultyLevel {
  easy,    // 80%+ mastery
  medium,  // 50-79% mastery
  hard,    // <50% mastery
}
```

### CoachPhrase

```dart
class CoachPhrase {
  final String id;
  final PhraseType type;
  final String text;
  final String audioPath;
  final EmotionLevel energy; // 1-5 scale
  final List<String> tags; // celebration, encouragement, try_again, etc.
}

enum PhraseType {
  celebration,
  encouragement,
  tryAgain,
  coaching,
  transition,
}

enum EmotionLevel {
  calm,       // 1
  friendly,   // 2
  enthusiastic, // 3
  excited,    // 4
  ecstatic,   // 5
}
```

---

## 🎬 Story Engine

### Word Selection Algorithm

```dart
class WordSelector {
  List<String> selectWordsForSession(
    SessionType type,
    LearningProgress progress,
    int currentWeek,
  ) {
    final vocabulary = WordList.getWordsForWeek(currentWeek);
    final allWords = progress.wordProgress;
    
    switch (type) {
      case SessionType.victoryLap:
        // 5-7 mastered words only
        return _selectMasteredWords(allWords, vocabulary, count: 5);
      
      case SessionType.growthChallenge:
        // 60% easy, 40% hard
        final easy = _selectMasteredWords(allWords, vocabulary, count: 3);
        final hard = _selectStrugglingWords(allWords, vocabulary, count: 2);
        return [...easy, ...hard]..shuffle();
      
      case SessionType.storyAdventure:
        // 50% easy, 30% medium, 20% hard
        final easy = _selectMasteredWords(allWords, vocabulary, count: 5);
        final medium = _selectLearningWords(allWords, vocabulary, count: 3);
        final hard = _selectStrugglingWords(allWords, vocabulary, count: 2);
        return [...easy, ...medium, ...hard];
    }
  }
  
  List<String> _selectMasteredWords(
    Map<String, WordProgress> allWords,
    List<String> vocabulary,
    {required int count}
  ) {
    return vocabulary
        .where((word) {
          final progress = allWords[word.toLowerCase()];
          return progress != null && progress.isMastered;
        })
        .take(count)
        .toList();
  }
  
  List<String> _selectStrugglingWords(
    Map<String, WordProgress> allWords,
    List<String> vocabulary,
    {required int count}
  ) {
    return vocabulary
        .where((word) {
          final progress = allWords[word.toLowerCase()];
          return progress != null && 
                 !progress.isMastered && 
                 progress.successRate < 0.5 &&
                 progress.totalAttempts >= 2;
        })
        .take(count)
        .toList();
  }
}
```

---

### Story Template System (MVP)

**Pre-written Templates:**

```dart
class StoryTemplates {
  static final List<StoryTemplate> templates = [
    StoryTemplate(
      id: 'magic_forest',
      title: 'The Magic Forest',
      theme: 'nature',
      beats: [
        StoryBeat(
          id: 'intro_1',
          type: BeatType.parentNarration,
          parentText: 'Once upon a time, [WORD_SLOT_0] were walking through a magical forest.',
        ),
        StoryBeat(
          id: 'child_1',
          type: BeatType.childPrompt,
          parentText: 'Can you say this word?',
          // App highlights [WORD_SLOT_0]
        ),
        StoryBeat(
          id: 'celebrate_1',
          type: BeatType.celebrationMoment,
          coachPhrase: 'celebration_perfect',
        ),
        // ... more beats
      ],
      wordSlots: [
        WordSlot(
          beatIndex: 0,
          wordPosition: 5, // "you" in sentence
          difficulty: DifficultyLevel.easy,
        ),
        // ... more slots
      ],
    ),
    
    // More templates: space adventure, ocean quest, etc.
  ];
}
```

**Runtime Word Insertion:**

```dart
class StoryBuilder {
  StoryTemplate buildSession(
    SessionType type,
    List<String> selectedWords,
  ) {
    // Select template based on type and child preferences
    final template = _selectTemplate(type);
    
    // Insert selected words into template slots
    final filledTemplate = _insertWords(template, selectedWords);
    
    // Add coaching moments for hard words
    final withCoaching = _addCoachingInterventions(filledTemplate, selectedWords);
    
    return withCoaching;
  }
  
  StoryTemplate _insertWords(
    StoryTemplate template,
    List<String> words,
  ) {
    final beats = template.beats.map((beat) {
      var text = beat.parentText;
      // Replace [WORD_SLOT_N] with actual words
      for (var i = 0; i < words.length; i++) {
        text = text.replaceAll('[WORD_SLOT_$i]', words[i].toUpperCase());
      }
      return beat.copyWith(parentText: text);
    }).toList();
    
    return template.copyWith(beats: beats);
  }
}
```

---

## 🎤 Speech Engine Integration

### Existing Speech Recognition (Child)

```dart
// Already implemented in SherpaRecognizer
class SherpaRecognizer {
  Stream<String> recognizeStream(); // Real-time recognition
  void setVocabulary(List<String> words); // Restrict to target words
}
```

### New: Parent Voice Activity Detection (Phase 2)

```dart
class ParentVoiceDetector {
  /// Detects when parent is speaking (not child)
  /// Uses voice characteristics (pitch, timbre) to differentiate
  Stream<VoiceActivity> detectActivity() async* {
    // Monitor audio input
    // Detect speech vs. silence
    // Estimate which word being spoken based on timing
  }
}

class VoiceActivity {
  final bool isSpeaking;
  final DateTime timestamp;
  final double confidence;
}
```

### Real-Time Highlighting (Phase 2)

```dart
class ReadingTracker {
  final ParentVoiceDetector voiceDetector;
  final List<Duration> expectedWordTimings; // From TTS baseline
  
  int currentWordIndex = 0;
  DateTime lastWordTime = DateTime.now();
  
  Stream<int> trackReading() async* {
    await for (final activity in voiceDetector.detectActivity()) {
      if (activity.isSpeaking) {
        final elapsed = DateTime.now().difference(lastWordTime);
        final expected = expectedWordTimings[currentWordIndex];
        
        // Within tolerance? Advance to next word
        if ((elapsed - expected).abs() < Duration(milliseconds: 500)) {
          yield currentWordIndex;
          currentWordIndex++;
          lastWordTime = DateTime.now();
        }
      }
    }
  }
}
```

---

## 🎨 UI Components

### ParentBubble Widget

```dart
class ParentBubble extends StatelessWidget {
  final String text;
  final List<HighlightedWord> highlights;
  final int? currentWordIndex;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.shade300, width: 2),
      ),
      child: Column(
        children: [
          // Parent icon
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.purple,
                child: Icon(Icons.person, color: Colors.white),
              ),
              SizedBox(width: 8),
              Text(
                'Read this:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          
          // Story text with highlighting
          RichText(
            text: TextSpan(
              children: _buildHighlightedText(text, highlights, currentWordIndex),
              style: TextStyle(fontSize: 18, color: Colors.black87, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
  
  List<TextSpan> _buildHighlightedText(
    String text,
    List<HighlightedWord> highlights,
    int? currentIndex,
  ) {
    // Implementation: split text, apply styling to current word
    // Fade words outside 5-word context window
  }
}
```

### ChildPromptWidget

```dart
class ChildPrompt extends StatelessWidget {
  final String word;
  final VoidCallback onSpoken;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade400, width: 3),
      ),
      child: Column(
        children: [
          Icon(Icons.mic, size: 48, color: Colors.amber.shade700),
          SizedBox(height: 12),
          Text(
            'Can you say this word?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(
            word.toUpperCase(),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
```

### CelebrationSequence

```dart
class CelebrationSequence extends StatefulWidget {
  final VoidCallback onComplete;
  
  @override
  _CelebrationSequenceState createState() => _CelebrationSequenceState();
}

class _CelebrationSequenceState extends State<CelebrationSequence>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _controller;
  int _step = 0; // 0: coach, 1: child tap, 2: prompt parent
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..forward();
    
    _playSequence();
  }
  
  Future<void> _playSequence() async {
    // Step 1: Coach celebrates
    await _coachService.playPhrase('celebration_awesome');
    await Future.delayed(Duration(milliseconds: 500));
    
    // Step 2: Prompt child high-five
    setState(() => _step = 1);
    await _waitForChildTap();
    
    // Step 3: Fireworks
    _showFireworks();
    await Future.delayed(Duration(milliseconds: 800));
    
    // Step 4: Prompt parent high-five
    setState(() => _step = 2);
    await _coachService.playPhrase('celebration_parent_highfive');
    
    await Future.delayed(Duration(seconds: 2));
    widget.onComplete();
  }
  
  Future<void> _waitForChildTap() async {
    // Wait for tap gesture
  }
  
  void _showFireworks() {
    // Trigger fireworks animation
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      child: _buildCurrentStep(),
    );
  }
  
  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildCoachCelebration();
      case 1:
        return _buildChildHighFive();
      case 2:
        return _buildParentPrompt();
      default:
        return SizedBox.shrink();
    }
  }
}
```

---

## 🤖 Coach Phrase System

### Phrase Library (MVP)

```dart
class CoachPhraseLibrary {
  static const Map<String, CoachPhrase> phrases = {
    // Celebrations
    'celebration_perfect': CoachPhrase(
      id: 'celebration_perfect',
      type: PhraseType.celebration,
      text: 'Perfect! That was AMAZING!',
      audioPath: 'assets/audio/coach/celebration_perfect.wav',
      energy: EmotionLevel.excited,
      tags: ['celebration', 'success'],
    ),
    
    'celebration_awesome': CoachPhrase(
      id: 'celebration_awesome',
      type: PhraseType.celebration,
      text: 'Awesome job! You\'re on fire!',
      audioPath: 'assets/audio/coach/celebration_awesome.wav',
      energy: EmotionLevel.ecstatic,
      tags: ['celebration', 'success'],
    ),
    
    // Encouragement
    'encouragement_try_again': CoachPhrase(
      id: 'encouragement_try_again',
      type: PhraseType.tryAgain,
      text: 'Good try! Let\'s practice that word together.',
      audioPath: 'assets/audio/coach/encouragement_try_again.wav',
      energy: EmotionLevel.friendly,
      tags: ['encouragement', 'growth_mindset'],
    ),
    
    // Coaching
    'coaching_hard_word': CoachPhrase(
      id: 'coaching_hard_word',
      type: PhraseType.coaching,
      text: 'This is a tricky one. Watch my mouth: [WORD]',
      audioPath: 'assets/audio/coach/coaching_hard_word.wav',
      energy: EmotionLevel.calm,
      tags: ['coaching', 'support'],
    ),
    
    // ... 20 total core phrases for MVP
  };
  
  static CoachPhrase getPhrase(String id) => phrases[id]!;
  
  static CoachPhrase getRandomCelebration() {
    final celebrations = phrases.values
        .where((p) => p.type == PhraseType.celebration)
        .toList();
    celebrations.shuffle();
    return celebrations.first;
  }
}
```

### Phrase Generation (ElevenLabs - Phase 2)

```dart
class CoachPhraseGenerator {
  final ElevenLabsAPI api;
  
  Future<void> generatePhraseLibrary() async {
    final prompts = [
      CoachPhrasePrompt(
        id: 'celebration_1',
        text: 'Wow, that was PERFECT!',
        emotion: '[excited, proud] Emphasize "PERFECT" with enthusiasm',
      ),
      CoachPhrasePrompt(
        id: 'encouragement_1',
        text: 'You\'ve got this! Try again!',
        emotion: '[encouraging, warm] Supportive but energetic',
      ),
      // ... 100+ prompts
    ];
    
    for (final prompt in prompts) {
      final audio = await api.generateSpeech(
        text: prompt.text,
        voice: 'friendly_coach', // Voice ID
        style: prompt.emotion,
      );
      
      await _saveAudio('assets/audio/coach/${prompt.id}.wav', audio);
    }
  }
}
```

### Modular Phrase Composition (Phase 3)

```dart
class ModularPhraseComposer {
  Future<AudioBuffer> composeCelebration({
    required int streakCount,
    required CelebrationType type,
  }) async {
    // Load individual phrase components
    final wow = await _loadAudio('coach/wow_excited.wav');
    final number = await _loadAudio('coach/numbers/$streakCount.wav');
    final inARow = await _loadAudio('coach/in_a_row.wav');
    final amazing = await _loadAudio('coach/amazing.wav');
    
    // Concatenate with slight pauses
    return _concatenateAudio([
      wow,
      _pause(100), // 100ms pause
      number,
      inARow,
      _pause(200),
      amazing,
    ]);
  }
}
```

---

## 📊 Spaced Repetition Engine

### Adaptive Word Progression (Phase 3)

```dart
class SpacedRepetitionEngine {
  /// Determines if child is ready to advance to next week
  bool canAdvanceToNextWeek(
    LearningProgress progress,
    int currentWeek,
  ) {
    final vocabulary = WordList.getWordsForWeek(currentWeek);
    final wordProgress = progress.wordProgress;
    
    // Criteria
    final masteredCount = vocabulary.where((word) {
      final wp = wordProgress[word.toLowerCase()];
      return wp != null && wp.isMastered;
    }).length;
    
    final masteryPercentage = masteredCount / vocabulary.length;
    final overallSuccessRate = progress.overallSuccessRate;
    final sessionCount = progress.totalSessions;
    final daysSinceStart = progress.daysSinceFirstSession;
    
    return masteryPercentage >= 0.8 &&
           overallSuccessRate >= 0.7 &&
           sessionCount >= 5 &&
           daysSinceStart >= 2;
  }
  
  /// Gradually introduce new words from next week
  List<String> selectVocabularyForNextSession(
    LearningProgress progress,
    int currentWeek,
  ) {
    final currentWeekWords = WordList.getWordsForWeek(currentWeek);
    final nextWeekWords = WordList.getWordsForWeek(currentWeek + 1);
    
    // Mastered words from current week
    final masteredCurrent = currentWeekWords.where((word) {
      final wp = progress.wordProgress[word.toLowerCase()];
      return wp != null && wp.isMastered;
    }).toList();
    
    // Not yet mastered from current week
    final learningCurrent = currentWeekWords.where((word) {
      final wp = progress.wordProgress[word.toLowerCase()];
      return wp == null || !wp.isMastered;
    }).toList();
    
    // If child has mastered most current week, introduce 1-2 from next
    if (masteredCurrent.length >= currentWeekWords.length * 0.7) {
      final newWords = nextWeekWords.take(2).toList();
      return [...learningCurrent, ...newWords]..shuffle();
    }
    
    // Otherwise, focus on current week
    return currentWeekWords;
  }
  
  /// Calculate optimal spacing for word repetition in story
  List<int> calculateWordRepetitionPoints(
    String word,
    WordProgress? progress,
    int storyLength,
  ) {
    final difficulty = _getDifficulty(progress);
    
    switch (difficulty) {
      case DifficultyLevel.easy:
        // Mastered: 2 appearances (beginning, end)
        return [0, storyLength - 1];
      
      case DifficultyLevel.medium:
        // Learning: 3 appearances (beginning, middle, end)
        return [0, storyLength ~/ 2, storyLength - 1];
      
      case DifficultyLevel.hard:
        // Struggling: 5 appearances with coaching
        return [
          0,
          storyLength ~/ 4,
          storyLength ~/ 2,
          (storyLength * 3) ~/ 4,
          storyLength - 1,
        ];
    }
  }
}
```

---

## 🎮 Session Controller

```dart
class CoachingSessionController extends ChangeNotifier {
  SessionType? _sessionType;
  StoryTemplate? _currentStory;
  int _currentBeatIndex = 0;
  List<WordAttempt> _attempts = [];
  DateTime? _startTime;
  
  // Services
  final WordSelector wordSelector;
  final StoryBuilder storyBuilder;
  final SherpaRecognizer speechRecognizer;
  final CoachPhraseLibrary phraseLibrary;
  final ProfileService profileService;
  
  /// Start a new coaching session
  Future<void> startSession({
    required SessionType type,
    required String childProfileId,
  }) async {
    _sessionType = type;
    _startTime = DateTime.now();
    
    // Load child's progress
    final progress = await profileService.loadProgress(childProfileId);
    if (progress == null) return;
    
    // Select words based on session type and mastery
    final selectedWords = wordSelector.selectWordsForSession(
      type,
      progress,
      await _getCurrentWeek(),
    );
    
    // Build story with selected words
    _currentStory = storyBuilder.buildSession(type, selectedWords);
    
    // Reset state
    _currentBeatIndex = 0;
    _attempts = [];
    
    notifyListeners();
  }
  
  /// Advance to next story beat
  Future<void> nextBeat() async {
    if (_currentStory == null) return;
    
    final beat = _currentStory!.beats[_currentBeatIndex];
    
    switch (beat.type) {
      case BeatType.parentNarration:
        // Parent reads, no interaction
        // (In Phase 2: track reading with VAD)
        break;
      
      case BeatType.childPrompt:
        // Enable speech recognition for target word
        await _handleChildPrompt(beat);
        break;
      
      case BeatType.coachIntervention:
        // Play coaching phrase
        await _playCoachPhrase(beat.coachPhrase!);
        break;
      
      case BeatType.celebrationMoment:
        // Trigger celebration sequence
        await _celebrationSequence();
        break;
    }
    
    _currentBeatIndex++;
    if (_currentBeatIndex >= _currentStory!.beats.length) {
      await _completeSession();
    }
    
    notifyListeners();
  }
  
  Future<void> _handleChildPrompt(StoryBeat beat) async {
    // Get target word from beat
    final word = _extractWordFromBeat(beat);
    
    // Enable recognition
    speechRecognizer.setVocabulary([word]);
    final result = await speechRecognizer.recognize();
    
    // Record attempt
    final correct = result.toLowerCase() == word.toLowerCase();
    _attempts.add(WordAttempt(
      word: word,
      correct: correct,
      timestamp: DateTime.now(),
    ));
    
    // Play appropriate response
    if (correct) {
      await _playCoachPhrase('celebration_perfect');
    } else {
      await _playCoachPhrase('encouragement_try_again');
      // Offer coaching
      await _coachingIntervention(word);
    }
  }
  
  Future<void> _celebrationSequence() async {
    // Trigger high-five animation
    // Play celebration audio
    // Haptic feedback
    // Wait for completion
  }
  
  Future<void> _completeSession() async {
    final duration = DateTime.now().difference(_startTime!);
    
    // Save session to profile
    final childProfileId = await profileService.getActiveProfileId();
    if (childProfileId != null) {
      final session = CoachingSession(
        id: _generateSessionId(),
        type: _sessionType!,
        childProfileId: childProfileId,
        targetWords: _extractWordsFromStory(),
        storyTemplate: _currentStory!.id,
        startTime: _startTime!,
        attempts: _attempts,
        celebrationCount: _countCelebrations(),
        duration: duration,
        easyWords: _countByDifficulty(DifficultyLevel.easy),
        mediumWords: _countByDifficulty(DifficultyLevel.medium),
        hardWords: _countByDifficulty(DifficultyLevel.hard),
      );
      
      await _saveSession(session);
    }
    
    // Show completion screen
    notifyListeners();
  }
}
```

---

## 📱 MVP Implementation Plan

### Phase 1: Manual Session (2-3 weeks)

**What to build:**
1. Session type selection (Victory Lap only for MVP)
2. Word selection algorithm (mastered words)
3. 5 pre-written story templates
4. Parent bubble UI (tap to advance)
5. Child prompt screen (manual advance)
6. Basic celebration sequence (no high-five choreography yet)
7. 20 pre-recorded coach phrases
8. Session tracking and save

**What to skip:**
- Real-time reading sync (VAD)
- Modular phrase composition
- LLM story generation
- Comic-style illustrations
- Spaced repetition optimization

**Result:**
- Functional parent-child experience
- Validates engagement model
- Testable with real families

---

### Technical Debt / Future Optimization

**Phase 2 additions:**
- VAD for real-time reading tracking
- Expanded phrase library (100+)
- Growth Challenge session type
- Better animations

**Phase 3 additions:**
- LLM story generation API
- Spaced repetition engine
- Modular phrase composition
- Story Adventure (full 20-min experience)

---

## 🧪 Testing Strategy

### Unit Tests
- Word selection algorithm
- Story template word insertion
- Spaced repetition calculations
- Difficulty categorization

### Integration Tests
- Session flow (start → beats → completion)
- Speech recognition integration
- Audio playback sequencing
- Progress saving

### User Testing
- 3-5 families for alpha
- Observe parent-child dynamics
- Measure completion rates
- Collect qualitative feedback
- Iterate on phrase energy, pacing, story quality

---

## 🎯 Success Criteria (MVP)

**Technical:**
- [ ] Session completes without crashes
- [ ] Audio plays smoothly (no stuttering)
- [ ] Child speech recognition works reliably
- [ ] Progress saves correctly

**User Experience:**
- [ ] 70%+ families complete first session
- [ ] Parents understand what to do (no confusion)
- [ ] Children engage with prompts
- [ ] Celebration moments feel rewarding

**Business:**
- [ ] Feature drives premium subscriptions
- [ ] Parents share experience (testimonials, social)
- [ ] Repeat usage (families come back for more stories)

---

This architecture is **ambitious but achievable** in phases. MVP focuses on proving the concept, then we iterate based on real family feedback.

