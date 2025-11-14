<!-- 47950e8c-c4e3-4ced-9865-9bc9db4d15ba 1f923c36-3e0b-4d24-b16a-b68ac2f9d10f -->
# Parent-Child Coaching Sessions: Interactive Story Time Prototype

## Phase 1: Commit Existing Work

Commit all pending dashboard changes and vision documents to establish baseline.

**Files to commit:**

- `lib/widgets/simple_progress_hero.dart`
- `lib/widgets/progress_timeline_widget.dart`
- `lib/widgets/action_words_widget.dart`
- `lib/screens/parent_dashboard_screen.dart` (simplified)
- `ideas/07_parent_child_coaching_sessions.md`
- `ideas/PARENT_COACHING_ARCHITECTURE.md`
- `ideas/TRANSFORMATIVE_IMPACT_ANALYSIS.md`
- `docs/SIMPLIFIED_DASHBOARD_DESIGN.md`
- `docs/SESSION_SUMMARY_SIMPLIFIED_DASHBOARD.md`

**Commit message:** "feat: Simplified parent dashboard and parent-child coaching vision"

---

## Phase 2: GenAI Infrastructure Setup

Create isolated, Docker-based GenAI services for story generation and TTS.

### 2.1 Project Structure

```
genai/
├── docker-compose.yml
├── .env.example
├── story_generator/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── src/
│   │   ├── story_api.py          # FastAPI service
│   │   ├── story_generator.py    # LLM story generation
│   │   ├── spaced_repetition.py  # Word spacing algorithm
│   │   └── prompts/
│   │       ├── story_arc.txt     # Epic series prompt
│   │       ├── daily_story.txt   # Single session prompt
│   │       └── coaching.txt      # Intervention prompts
│   └── tests/
└── tts_service/
    ├── Dockerfile
    ├── requirements.txt
    └── src/
        ├── tts_api.py            # FastAPI service
        └── elevenlabs_client.py  # ElevenLabs integration
```

### 2.2 Story Generator Service

**`story_generator/Dockerfile`:**

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY src/ ./src/
CMD ["uvicorn", "src.story_api:app", "--host", "0.0.0.0", "--port", "8001"]
```

**`story_generator/requirements.txt`:**

```
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
openai==1.3.5  # For OpenRouter compatibility
```

**Key API endpoints:**

- `POST /generate-story` - Generate single story session
- `POST /generate-epic` - Generate multi-story arc
- `POST /calculate-spacing` - Spaced repetition for words

### 2.3 Environment Variables

**`.env.example`:**

```
OPENROUTER_API_KEY=your_key_here
ELEVENLABS_API_KEY=your_key_here
DEFAULT_MODEL=anthropic/claude-3.5-sonnet
```

### 2.4 Docker Compose

**`docker-compose.yml`:**

```yaml
version: '3.8'
services:
  story_generator:
    build: ./story_generator
    ports:
      - "8001:8001"
    env_file:
      - .env
    volumes:
      - ./story_generator/src:/app/src

  tts_service:
    build: ./tts_service
    ports:
      - "8002:8002"
    env_file:
      - .env
    volumes:
      - ./tts_service/src:/app/src
      - ./generated_audio:/app/output
```

---

## Phase 3: Core Data Models

Create extensible, JSON-serializable data structures for stories and sessions.

### 3.1 Story Models

**`lib/models/story_models.dart`:**

```dart
class StoryArc {
  final String id;
  final String title;
  final String theme;
  final List<StoryChapter> chapters;
  final StoryProgress progress;
}

class StoryChapter {
  final String id;
  final int chapterNumber;
  final String title;
  final List<StoryBeat> beats;
  final List<ChoicePoint> choicePoints;
}

class StoryBeat {
  final String id;
  final BeatType type;  // narration, child_turn, coach_intervention, celebration
  final String text;
  final String? speaker;  // 'parent', 'coach', 'child'
  final List<String> targetWords;
  final String? coachPhrase;
}

class ChoicePoint {
  final String id;
  final String promptText;
  final List<StoryChoice> choices;
}

class StoryChoice {
  final String id;
  final String previewText;  // Show as comic panel
  final String choiceText;
  final List<StoryBeat> consequenceBeats;
}
```

### 3.2 Session Models

**`lib/models/coaching_session.dart`:**

```dart
class CoachingSession {
  final String id;
  final String profileId;
  final String storyArcId;
  final String chapterId;
  final DateTime startTime;
  final List<WordAttempt> wordAttempts;
  final List<ChoiceMade> choicesMade;
  final SessionMetrics metrics;
}

class SessionMetrics {
  final int wordsAttempted;
  final int wordsCorrect;
  final int celebrationCount;
  final Duration duration;
  final Map<String, double> wordConfidence;  // word -> confidence score
}
```

### 3.3 Story Preferences

**`lib/models/story_preferences.dart`:**

```dart
class StoryPreferences {
  final String childName;
  final String protagonistName;
  final List<String> favoriteThemes;  // unicorns, space, ocean, etc.
  final List<String> favoriteCharacters;
  final String storyTone;  // adventure, whimsical, heroic
  final int difficultyLevel;  // 1-5
  final bool allowChoicePoints;
}
```

---

## Phase 4: Story Generation Service

Implement LLM-powered story generation with spaced repetition logic.

### 4.1 Spaced Repetition Algorithm

**`genai/story_generator/src/spaced_repetition.py`:**

```python
def calculate_word_spacing(
    word: str,
    mastery_level: float,  # 0.0 - 1.0
    story_length: int,
    beats: int
) -> List[int]:
    """Calculate optimal beat positions for word repetition."""
    
    if mastery_level >= 0.8:  # Mastered
        return [0, beats - 1]  # Beginning and end
    elif mastery_level >= 0.5:  # Learning
        return [0, beats // 2, beats - 1]  # Beginning, middle, end
    else:  # Struggling
        # More frequent: 0, 25%, 50%, 75%, 100%
        positions = [
            0,
            beats // 4,
            beats // 2,
            (beats * 3) // 4,
            beats - 1
        ]
        return [p for p in positions if p < beats]
```

### 4.2 Story Generation Prompt

**`genai/story_generator/src/prompts/daily_story.txt`:**

```
You are a master storyteller creating an interactive parent-child reading experience.

CONTEXT:
- Child: {child_name}, Age {age}
- Protagonist: {protagonist_name}
- Theme: {theme}
- Story arc position: Chapter {chapter_num} of {total_chapters}

TARGET WORDS (must appear at specified beats):
{word_insertions}

STORY REQUIREMENTS:
1. Length: Exactly {num_beats} beats (1 beat = 1-2 sentences)
2. Structure:
   - Beats 1-3: Setup, comfort zone
   - Beats 4-6: Challenge emerges
   - Beats 7-9: Struggle and growth
   - Beats 10-12: Resolution, triumph
3. Emotional tone: Encouraging, validating struggle, celebrating effort
4. Growth mindset: Show hero trying, failing, learning, succeeding

BEAT TYPES:
- NARRATION: Parent reads to child
- CHILD_TURN: Child says target word
- COACHING: Coach helps with hard word
- CELEBRATION: Group high-five moment

CHOICE POINTS:
- Include {num_choices} choice points where child picks story direction
- Choices should feel meaningful but not stressful
- Both paths lead to growth and learning

OUTPUT FORMAT: JSON with beats array, choice points, and coaching moments.
```

### 4.3 Story API

**`genai/story_generator/src/story_api.py`:**

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import openai

app = FastAPI()

class StoryRequest(BaseModel):
    child_name: str
    age: int
    theme: str
    target_words: List[Dict[str, Any]]  # word, mastery_level
    chapter_num: int
    total_chapters: int
    num_choices: int = 2

@app.post("/generate-story")
async def generate_story(request: StoryRequest):
    # Calculate word spacing
    word_insertions = calculate_spacing_for_all_words(
        request.target_words,
        num_beats=12
    )
    
    # Load prompt template
    prompt = load_prompt_template("daily_story.txt").format(
        child_name=request.child_name,
        age=request.age,
        theme=request.theme,
        word_insertions=word_insertions,
        chapter_num=request.chapter_num,
        total_chapters=request.total_chapters,
        num_beats=12,
        num_choices=request.num_choices
    )
    
    # Call OpenRouter
    response = await call_openrouter(prompt)
    
    # Parse and validate story structure
    story = parse_story_json(response)
    
    return story
```

---

## Phase 5: Flutter Integration

Build the coaching session UI with native TTS and clean orchestration.

### 5.1 Coaching Session Controller

**`lib/controllers/coaching_session_controller.dart`:**

```dart
class CoachingSessionController extends ChangeNotifier {
  StoryChapter? _currentChapter;
  int _currentBeatIndex = 0;
  List<WordAttempt> _attempts = [];
  
  final FlutterTts _tts = FlutterTts();
  final SherpaRecognizer _speechRecognizer;
  
  Future<void> startSession(String profileId) async {
    // Load story for this profile
    final story = await _loadOrGenerateStory(profileId);
    _currentChapter = story;
    _currentBeatIndex = 0;
    notifyListeners();
  }
  
  Future<void> nextBeat() async {
    if (_currentChapter == null) return;
    
    final beat = _currentChapter!.beats[_currentBeatIndex];
    
    switch (beat.type) {
      case BeatType.narration:
        // Parent reads - just advance
        break;
        
      case BeatType.childTurn:
        // Enable speech recognition
        await _handleChildTurn(beat);
        break;
        
      case BeatType.coachIntervention:
        // Coach speaks via TTS
        await _speakCoachPhrase(beat.coachPhrase!);
        break;
        
      case BeatType.celebration:
        // Trigger celebration sequence
        await _triggerCelebration();
        break;
    }
    
    _currentBeatIndex++;
    if (_currentBeatIndex >= _currentChapter!.beats.length) {
      await _handleChoicePoint();
    }
    
    notifyListeners();
  }
  
  Future<void> _speakCoachPhrase(String phrase) async {
    await _tts.speak(phrase);
    await _tts.awaitSpeakCompletion(true);
  }
}
```

### 5.2 Story Reader UI

**`lib/screens/story_reader_screen.dart`:**

```dart
class StoryReaderScreen extends StatelessWidget {
  Widget build(BuildContext context) {
    return Consumer<CoachingSessionController>(
      builder: (context, controller, _) {
        final beat = controller.currentBeat;
        
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Comic panel display (previous beat on left)
                Expanded(
                  flex: 2,
                  child: _buildComicPanels(controller),
                ),
                
                // Current beat display
                Expanded(
                  flex: 3,
                  child: _buildCurrentBeat(beat),
                ),
                
                // Navigation
                _buildNavigation(controller),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildCurrentBeat(StoryBeat beat) {
    switch (beat.type) {
      case BeatType.narration:
        return ParentNarrationBubble(text: beat.text);
      case BeatType.childTurn:
        return ChildPromptWidget(
          targetWord: beat.targetWords.first,
          onSpoken: () => controller.recordAttempt(),
        );
      case BeatType.celebration:
        return CelebrationWidget();
      default:
        return CoachSpeechBubble(text: beat.text);
    }
  }
}
```

### 5.3 Choice Point UI

**`lib/widgets/choice_point_widget.dart`:**

```dart
class ChoicePointWidget extends StatelessWidget {
  final ChoicePoint choicePoint;
  final Function(StoryChoice) onChoiceSelected;
  
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Previous story panel
        ComicPanel(text: "What happened last..."),
        
        SizedBox(height: 20),
        
        // Choice prompt
        Text(
          choicePoint.promptText,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        
        SizedBox(height: 20),
        
        // Two choice panels side by side
        Row(
          children: choicePoint.choices.map((choice) {
            return Expanded(
              child: GestureDetector(
                onTap: () => onChoiceSelected(choice),
                child: ComicPanel(
                  text: choice.previewText,
                  subtitle: choice.choiceText,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
```

---

## Phase 6: Dashboard Integration

Restructure dashboard to make story time the primary action.

### 6.1 Update Dashboard Layout

**Modify `lib/screens/parent_dashboard_screen.dart`:**

Add prominent "Start Story Time" button at top of dashboard:

```dart
Widget _buildDashboard(BuildContext context, LearningProgress progress) {
  return SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        // PRIMARY ACTION: Start Story Time
        _buildStartStoryButton(context),
        
        SizedBox(height: 24),
        
        // Hero section (existing)
        SimpleProgressHero(...),
        
        // Timeline (existing)
        ProgressTimelineWidget(...),
        
        // Settings quick access
        _buildQuickSettings(context),
        
        // ... rest of dashboard
      ],
    ),
  );
}

Widget _buildStartStoryButton(BuildContext context) {
  return ElevatedButton(
    onPressed: () => _launchStorySession(context),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.deepPurple,
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.auto_stories, size: 32),
        SizedBox(width: 12),
        Text(
          'Start Story Time',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}
```

### 6.2 Move Settings Under Dashboard

Update game screen to make dashboard the primary parent button:

**Modify `lib/widgets/game_screen.dart`:**

Change settings button to parent dashboard button:

```dart
// Replace settings button with parent dashboard button
ParentalGatedIconButton(
  icon: Icons.dashboard,  // Changed from settings
  tooltip: 'Parent Dashboard',
  onVerified: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ParentDashboardScreen()),
    );
  },
)
```

Add settings as a card in dashboard:

```dart
Widget _buildQuickSettings(BuildContext context) {
  return Card(
    child: ListTile(
      leading: Icon(Icons.settings),
      title: Text('Settings & Preferences'),
      subtitle: Text('Customize story themes, difficulty'),
      trailing: Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SettingsPage()),
      ),
    ),
  );
}
```

---

## Phase 7: Story Generation Flow

Connect Flutter to GenAI service for dynamic story generation.

### 7.1 Story Service

**`lib/services/story_service.dart`:**

```dart
class StoryService {
  final String _baseUrl = 'http://localhost:8001';
  
  Future<StoryChapter> generateStory({
    required String profileId,
    required StoryPreferences preferences,
  }) async {
    // Get child's word progress
    final progress = await ProfileService().loadProgress(profileId);
    
    // Select target words based on mastery
    final targetWords = _selectTargetWords(progress);
    
    // Call story generation API
    final response = await http.post(
      Uri.parse('$_baseUrl/generate-story'),
      body: jsonEncode({
        'child_name': preferences.childName,
        'age': preferences.childAge,
        'theme': preferences.favoriteThemes.first,
        'target_words': targetWords.map((w) => {
          'word': w.word,
          'mastery_level': w.successRate,
        }).toList(),
        'chapter_num': preferences.currentChapter,
        'total_chapters': 10,
        'num_choices': 2,
      }),
    );
    
    if (response.statusCode == 200) {
      return StoryChapter.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to generate story');
    }
  }
  
  List<WordProgress> _selectTargetWords(LearningProgress progress) {
    // 60% easy, 40% challenging
    final easy = progress.wordProgress.values
        .where((w) => w.successRate >= 0.7)
        .take(3)
        .toList();
    
    final challenging = progress.wordProgress.values
        .where((w) => w.successRate < 0.7)
        .take(2)
        .toList();
    
    return [...easy, ...challenging];
  }
}
```

---

## Phase 8: Rapid Iteration Setup

Tools and workflows for fast prototyping and testing.

### 8.1 Story Testing Tool

**`genai/story_generator/src/test_story.py`:**

```python
#!/usr/bin/env python3
"""Quick CLI tool to generate and preview stories."""

import requests
import json
from rich.console import Console
from rich.markdown import Markdown

console = Console()

def generate_test_story():
    response = requests.post(
        "http://localhost:8001/generate-story",
        json={
            "child_name": "Adalyn",
            "age": 5,
            "theme": "unicorn adventure",
            "target_words": [
                {"word": "you", "mastery_level": 0.9},
                {"word": "see", "mastery_level": 0.8},
                {"word": "her", "mastery_level": 0.3},
            ],
            "chapter_num": 1,
            "total_chapters": 5,
            "num_choices": 2
        }
    )
    
    story = response.json()
    
    # Pretty print story
    console.print("\n[bold magenta]Generated Story:[/bold magenta]\n")
    for beat in story['beats']:
        speaker = beat.get('speaker', 'narrator')
        text = beat['text']
        console.print(f"[cyan]{speaker}:[/cyan] {text}\n")
    
    return story

if __name__ == "__main__":
    generate_test_story()
```

### 8.2 Hot Reload for Story Templates

Mount prompt templates as volumes in Docker so changes are instant:

```yaml
# In docker-compose.yml
volumes:
  - ./story_generator/src/prompts:/app/prompts:ro
```

### 8.3 Story Preview in App

Add developer mode button in dashboard (debug builds only):

```dart
if (kDebugMode) {
  ElevatedButton(
    onPressed: () => _previewGeneratedStory(),
    child: Text('Preview Story (Dev)'),
  )
}
```

---

## Implementation Order

1. Commit existing work
2. Set up GenAI infrastructure (Docker, services)
3. Create core data models (story, session)
4. Implement spaced repetition algorithm
5. Build story generation service
6. Create story reader UI
7. Integrate with dashboard
8. Test and iterate on story quality
9. Add choice points
10. Refine coaching phrases and celebrations

## Success Criteria

- Parent can launch story session from dashboard in 1 tap
- Stories feel personalized and engaging
- Word spacing feels natural (not forced)
- Parent/child/coach handoff is smooth
- Choice points feel meaningful
- Can iterate on story prompts in <5 minutes
- System generates unique stories each time

## Future Enhancements (Out of Scope)

- Epic story arc tracking (multi-chapter series)
- Parent story preview/steering
- Advanced choice consequence tracking
- ElevenLabs audio integration
- Visual comic panel generation
- Classroom/teacher mode

### To-dos

- [ ] Commit simplified dashboard and vision documents
- [ ] Set up Docker-based GenAI infrastructure (story generator + TTS services)
- [ ] Create story and session data models (StoryArc, StoryChapter, StoryBeat, CoachingSession)
- [ ] Implement spaced repetition algorithm for word placement
- [ ] Build story generation API with OpenRouter integration
- [ ] Create story reader UI with parent/child/coach orchestration
- [ ] Integrate story time button into dashboard as primary action
- [ ] Test story generation, iterate on prompts and flow