# Xen Words GenAI Services

Docker-based AI services for story generation and text-to-speech.

## Services

### Story Generator (Port 8001)
- LLM-powered story generation via OpenRouter
- Spaced repetition word placement
- Epic arc creation
- Choice-based narratives

### TTS Service (Port 8002)
- ElevenLabs integration (future)
- Audio generation for coach phrases
- Voice customization

## Setup

### 1. Configure API Keys

```bash
cd genai
cp env.example .env
# Edit .env and add your actual API keys
```

### 2. Start Services

```bash
docker-compose up -d
```

### 3. Check Health

```bash
curl http://localhost:8001/health
curl http://localhost:8002/health
```

## API Usage

### Generate a Story

```bash
curl -X POST http://localhost:8001/generate-story \
  -H "Content-Type: application/json" \
  -d '{
    "child_name": "Adalyn",
    "age": 5,
    "theme": "adventure",
    "target_words": [
      {"word": "you", "mastery_level": 0.9},
      {"word": "see", "mastery_level": 0.8},
      {"word": "her", "mastery_level": 0.3}
    ],
    "chapter_num": 1,
    "total_chapters": 10,
    "num_choices": 2
  }'
```

### Generate Epic Arc

```bash
curl -X POST http://localhost:8001/generate-epic \
  -H "Content-Type: application/json" \
  -d '{
    "child_name": "Adalyn",
    "age": 5,
    "theme": "magic",
    "total_weeks": 25,
    "total_words": 100
  }'
```

### Calculate Word Spacing

```bash
curl -X POST http://localhost:8001/calculate-spacing \
  -H "Content-Type: application/json" \
  -d '{
    "words": [
      {"word": "you", "mastery_level": 0.9},
      {"word": "her", "mastery_level": 0.3}
    ],
    "num_beats": 12
  }'
```

## Development

### Hot Reload

Source code is mounted as a volume, so changes are reflected immediately without rebuild.

### View Logs

```bash
docker-compose logs -f story_generator
```

### Test Story Generation

```bash
cd story_generator
python3 -m src.test_story
```

## Models

Default: `anthropic/claude-3.5-sonnet` via OpenRouter

See `.env` to configure different models.

## Architecture

```
genai/
├── story_generator/       # Story generation service
│   ├── src/
│   │   ├── story_api.py           # FastAPI endpoints
│   │   ├── story_generator.py     # LLM story creation
│   │   └── spaced_repetition.py   # Word spacing logic
│   ├── Dockerfile
│   └── requirements.txt
├── tts_service/           # TTS service (future)
├── docker-compose.yml     # Orchestration
└── .env                   # API keys (gitignored)
```

## Flutter Integration

From Flutter app:

```dart
import 'package:http/http.dart' as http;

final response = await http.post(
  Uri.parse('http://localhost:8001/generate-story'),
  body: jsonEncode({...}),
);

final story = jsonDecode(response.body);
```

## Troubleshooting

**Service won't start:**
- Check `.env` file exists and has valid API keys
- Run `docker-compose logs story_generator`

**Story generation fails:**
- Verify OpenRouter API key is valid
- Check model quota/credits
- View logs for detailed error

**Hot reload not working:**
- Ensure volumes are properly mounted
- Restart with `docker-compose restart story_generator`

