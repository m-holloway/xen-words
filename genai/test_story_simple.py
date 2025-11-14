#!/usr/bin/env python3
"""
Simple story generation test without FastAPI dependencies.
Calls OpenRouter directly to generate a story.
"""
import json
import os
import sys
from pathlib import Path

# Add parent directory to path to load .env
sys.path.insert(0, str(Path(__file__).parent))

# Simple HTTP client using urllib (built-in)
import urllib.request
import urllib.error

# Load environment variables manually
def load_env():
    env_file = Path(__file__).parent / '.env'
    env_vars = {}
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key] = value
    return env_vars

env = load_env()
OPENROUTER_API_KEY = env.get('OPENROUTER_API_KEY', '')
DEFAULT_MODEL = env.get('DEFAULT_MODEL', 'anthropic/claude-3.5-sonnet')

if not OPENROUTER_API_KEY:
    print("❌ ERROR: OPENROUTER_API_KEY not found in .env file")
    sys.exit(1)

# Spaced repetition logic (simplified)
def calculate_word_spacing(word, mastery_level, num_beats=12):
    """Calculate beat positions for a word based on mastery."""
    if mastery_level >= 0.8:
        # Mastered: beginning and end
        return [0, num_beats - 1]
    elif mastery_level >= 0.5:
        # Learning: beginning, middle, end
        mid = num_beats // 2
        return [0, mid, num_beats - 1]
    else:
        # Struggling: frequent repetition
        return [0, num_beats // 4, num_beats // 2, (num_beats * 3) // 4, num_beats - 1]

def build_story_prompt(child_name, age, theme, target_words):
    """Build the LLM prompt for story generation."""
    
    # Calculate word spacing
    word_spacing = {}
    for word, mastery in target_words:
        word_spacing[word] = calculate_word_spacing(word, mastery)
    
    # Format word list
    word_list = "\n".join([
        f"- '{word}' appears at beats: {', '.join(map(str, beats))}"
        for word, beats in word_spacing.items()
    ])
    
    # Determine tone
    avg_mastery = sum(m for _, m in target_words) / len(target_words)
    if avg_mastery >= 0.8:
        tone = "celebratory"
    elif avg_mastery >= 0.6:
        tone = "encouraging"
    else:
        tone = "supportive"
    
    protagonist = child_name
    
    return f"""You are a master storyteller creating an interactive parent-child reading experience for {child_name}, age {age}.

STORY REQUIREMENTS:
- Theme: {theme}
- Protagonist: {protagonist}
- Chapter: 1 of 10
- Tone: {tone}
- Length: Exactly 12 beats (1 beat = 1-2 sentences)

TARGET WORDS (must appear at specified beats):
{word_list}

BEAT STRUCTURE:
Each beat should be tagged with a type:
1. NARRATION - Parent reads to child (exposition, scene-setting)
2. CHILD_TURN - Child says the target word (prompt them clearly)
3. COACHING - Coach helps with a difficult word (encouraging guidance)
4. CELEBRATION - Group celebration moment (high-fives, fireworks)

STORY PROGRESSION:
- Beats 1-3: Setup, comfort zone, introduce challenge
- Beats 4-6: Challenge emerges, tension builds
- Beats 7-9: Struggle and growth, emotional moment
- Beats 10-12: Resolution, triumph, celebration

CHOICE POINTS:
- Include 2 choice points where child picks story direction
- Place choices at beats 5 and 9
- Each choice should feel meaningful but not stressful
- Both options lead to growth

EMOTIONAL THEMES:
- Growth mindset: Show protagonist trying, failing, learning, succeeding
- Vulnerability: It's okay to need help
- Celebration of effort: Trying is what matters
- Connection: Parent/coach are allies in the journey

OUTPUT FORMAT:
Return ONLY a valid JSON object (no markdown, no explanation) with this structure:
{{
  "id": "story_1",
  "title": "Story Title",
  "beats": [
    {{
      "type": "narration",
      "text": "The text of the beat",
      "speaker": "parent",
      "target_words": [],
      "coach_phrase": null
    }},
    {{
      "type": "child_turn",
      "text": "Now {protagonist}, can you say the word 'see'?",
      "speaker": "coach",
      "target_words": ["see"],
      "coach_phrase": "You got this!"
    }}
  ],
  "choice_points": [
    {{
      "id": "choice_1",
      "beat_index": 5,
      "prompt_text": "What should {protagonist} do?",
      "choices": [
        {{
          "id": "choice_1a",
          "preview_text": "Path 1 preview",
          "choice_text": "Choose this path"
        }},
        {{
          "id": "choice_1b",
          "preview_text": "Path 2 preview",
          "choice_text": "Choose that path"
        }}
      ]
    }}
  ]
}}

IMPORTANT:
- Make the story engaging and age-appropriate for a {age}-year-old
- Natural language flow - word placement should feel organic
- Clear cues for when child should speak
- Encouraging tone throughout
- Reference the target words naturally in context

Generate the story now:"""

def call_openrouter(prompt):
    """Call OpenRouter API."""
    url = "https://openrouter.ai/api/v1/chat/completions"
    
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json"
    }
    
    data = {
        "model": DEFAULT_MODEL,
        "messages": [
            {
                "role": "system",
                "content": "You are a creative storyteller specializing in educational content for young children. You always respond with valid JSON."
            },
            {
                "role": "user",
                "content": prompt
            }
        ],
        "temperature": 0.8,
        "max_tokens": 2000
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode('utf-8'),
        headers=headers,
        method='POST'
    )
    
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result['choices'][0]['message']['content']
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        raise Exception(f"OpenRouter API error {e.code}: {error_body}")
    except Exception as e:
        raise Exception(f"Request failed: {str(e)}")

def main():
    print("🚀 Testing Story Generation")
    print("=" * 60)
    
    # Test data
    child_name = "Adalyn"
    age = 5
    theme = "adventure"
    target_words = [
        ("you", 0.9),   # Mastered
        ("see", 0.8),   # Mastered
        ("go", 0.7),    # Learning
        ("her", 0.3),   # Struggling
        ("what", 0.4),  # Struggling
    ]
    
    print(f"\n👧 Child: {child_name} (age {age})")
    print(f"🎨 Theme: {theme}")
    print(f"📝 Target words:")
    for word, mastery in target_words:
        level = "✅ Mastered" if mastery >= 0.8 else "📚 Learning" if mastery >= 0.5 else "🎯 Struggling"
        print(f"   - '{word}' ({mastery:.1f}) {level}")
    
    print(f"\n🤖 Model: {DEFAULT_MODEL}")
    print("\n⏳ Generating story...")
    
    try:
        # Build prompt
        prompt = build_story_prompt(child_name, age, theme, target_words)
        
        # Call API
        response = call_openrouter(prompt)
        
        # Extract JSON
        json_start = response.find("{")
        json_end = response.rfind("}") + 1
        json_str = response[json_start:json_end]
        
        story = json.loads(json_str)
        
        # Display results
        print("\n" + "=" * 60)
        print("✅ Story Generated Successfully!")
        print("=" * 60)
        
        print(f"\n📖 Title: {story.get('title', 'Untitled')}")
        print(f"🎬 Beats: {len(story.get('beats', []))}")
        print(f"🔀 Choice Points: {len(story.get('choice_points', []))}")
        
        print("\n📜 Story Beats:")
        for i, beat in enumerate(story.get('beats', []), 1):
            beat_type = beat.get('type', 'unknown')
            text = beat.get('text', '')
            words = beat.get('target_words', [])
            
            icon = {
                'narration': '👨‍👩‍👧',
                'child_turn': '👧',
                'coaching': '🎓',
                'celebration': '🎉'
            }.get(beat_type, '📌')
            
            print(f"\n  {i}. {icon} {beat_type.upper()}")
            print(f"     {text[:100]}{'...' if len(text) > 100 else ''}")
            if words:
                print(f"     🎯 Target words: {', '.join(words)}")
        
        print("\n🔀 Choice Points:")
        for cp in story.get('choice_points', []):
            print(f"\n  At beat {cp.get('beat_index', 0)}:")
            print(f"  ❓ {cp.get('prompt_text', '')}")
            for choice in cp.get('choices', []):
                print(f"     • {choice.get('choice_text', '')}")
        
        # Save to file
        output_file = Path(__file__).parent / "generated_story_sample.json"
        with open(output_file, 'w') as f:
            json.dump(story, f, indent=2)
        
        print(f"\n💾 Full story saved to: {output_file}")
        print("\n" + "=" * 60)
        print("✨ Test Complete!")
        
    except Exception as e:
        print(f"\n❌ Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()

