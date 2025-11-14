"""
Story Generator

LLM-powered story generation with word placement and epic arc creation.
"""
import os
import json
import uuid
from typing import List, Tuple, Optional, Dict, Any
from pathlib import Path

from .spaced_repetition import (
    calculate_spacing_for_all_words,
    get_difficulty_distribution,
    suggest_story_tone
)


class StoryGenerator:
    """Generates stories using LLM with spaced repetition word placement."""
    
    def __init__(self, openai_client):
        """
        Initialize story generator.
        
        Args:
            openai_client: OpenAI client configured for OpenRouter
        """
        self.client = openai_client
        self.model = os.getenv("DEFAULT_MODEL", "anthropic/claude-3.5-sonnet")
        self.prompts_dir = Path("/app/prompts")
        
    async def generate_chapter(
        self,
        child_name: str,
        protagonist_name: str,
        age: int,
        theme: str,
        target_words: List[Tuple[str, float]],  # (word, mastery)
        chapter_num: int,
        total_chapters: int,
        num_choices: int = 2,
        epic_context: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Generate a single story chapter.
        
        Returns a structured story with beats, choice points, and word placement.
        """
        # Calculate word spacing
        word_spacing = calculate_spacing_for_all_words(target_words, num_beats=12)
        
        # Get story tone based on difficulty
        tone = suggest_story_tone(target_words)
        
        # Load prompt template
        prompt = self._build_chapter_prompt(
            child_name=child_name,
            protagonist_name=protagonist_name,
            age=age,
            theme=theme,
            word_spacing=word_spacing,
            chapter_num=chapter_num,
            total_chapters=total_chapters,
            num_choices=num_choices,
            tone=tone,
            epic_context=epic_context,
        )
        
        # Call LLM
        response = await self._call_llm(prompt)
        
        # Parse and structure the story
        story = self._parse_story_response(response, word_spacing)
        
        # Add metadata
        story["metadata"] = {
            "chapter_num": chapter_num,
            "total_chapters": total_chapters,
            "theme": theme,
            "tone": tone,
            "word_count": len(target_words),
            "difficulty_distribution": get_difficulty_distribution(target_words),
        }
        
        return story
    
    async def generate_epic_arc(
        self,
        child_name: str,
        protagonist_name: str,
        age: int,
        theme: str,
        total_weeks: int,
        total_words: int,
    ) -> Dict[str, Any]:
        """
        Generate an epic arc structure for the entire learning journey.
        
        Returns a high-level outline with milestones and narrative beats.
        """
        prompt = self._build_epic_prompt(
            child_name=child_name,
            protagonist_name=protagonist_name,
            age=age,
            theme=theme,
            total_weeks=total_weeks,
            total_words=total_words,
        )
        
        response = await self._call_llm(prompt)
        
        # Parse epic structure
        epic = self._parse_epic_response(response)
        
        return epic
    
    def _build_chapter_prompt(
        self,
        child_name: str,
        protagonist_name: str,
        age: int,
        theme: str,
        word_spacing: Dict[str, List[int]],
        chapter_num: int,
        total_chapters: int,
        num_choices: int,
        tone: str,
        epic_context: Optional[str],
    ) -> str:
        """Build the LLM prompt for chapter generation."""
        
        # Format word spacing for prompt
        word_list = "\n".join([
            f"- '{word}' appears at beats: {', '.join(map(str, beats))}"
            for word, beats in word_spacing.items()
        ])
        
        epic_section = f"\n\nEPIC CONTEXT:\n{epic_context}" if epic_context else ""
        
        return f"""You are a master storyteller creating an interactive parent-child reading experience for {child_name}, age {age}.

STORY REQUIREMENTS:
- Theme: {theme}
- Protagonist: {protagonist_name}
- Chapter: {chapter_num} of {total_chapters}
- Tone: {tone}
- Length: Exactly 12 beats (1 beat = 1-2 sentences)
{epic_section}

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
- Include {num_choices} choice points where child picks story direction
- Place choices at beats 5 and 9
- Each choice should:
  * Feel meaningful but not stressful
  * Both options lead to growth
  * Be presented as 1-2 sentence previews

EMOTIONAL THEMES:
- Growth mindset: Show protagonist trying, failing, learning, succeeding
- Vulnerability: It's okay to need help
- Celebration of effort: Trying is what matters
- Connection: Parent/coach are allies in the journey

OUTPUT FORMAT:
Return a JSON object with this structure:
{{
  "id": "unique_story_id",
  "title": "Story Title",
  "beats": [
    {{
      "type": "narration|child_turn|coaching|celebration",
      "text": "The text of the beat",
      "speaker": "parent|coach|child",
      "target_words": ["word1", "word2"],
      "coach_phrase": "Optional coaching phrase if type is coaching"
    }}
  ],
  "choice_points": [
    {{
      "id": "choice_1",
      "beat_index": 5,
      "prompt_text": "What should {protagonist_name} do?",
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
    
    def _build_epic_prompt(
        self,
        child_name: str,
        protagonist_name: str,
        age: int,
        theme: str,
        total_weeks: int,
        total_words: int,
    ) -> str:
        """Build the LLM prompt for epic arc generation."""
        
        return f"""You are creating an epic story arc for {child_name}'s learning journey to mastery of sight words.

HERO: {protagonist_name} (representing {child_name})
THEME: {theme}
DURATION: {total_weeks} weeks
GOAL: Master {total_words} sight words

Create a hero's journey structure with these elements:

ACT 1 - THE CALL (Weeks 1-{total_weeks // 4}):
- Protagonist discovers the world of magic words
- Each word mastered grants a new ability/power
- Mentor (coach) provides guidance
- First milestone: Master foundation words

ACT 2 - TRIALS (Weeks {total_weeks // 4 + 1}-{total_weeks // 2}):
- Hero faces increasingly difficult challenges
- Setbacks and struggles (harder words)
- Emotional growth: persistence, asking for help
- Allies gained (parent support reflected in story)

ACT 3 - THE ORDEAL (Weeks {total_weeks // 2 + 1}-{total_weeks * 3 // 4}):
- Toughest words present greatest challenge
- Hero must use all learned skills
- Parent's role crucial (coaching moments)
- Near-failures followed by breakthroughs

ACT 4 - RETURN WITH MASTERY (Final {total_weeks // 4} weeks):
- All words mastered = full hero powers
- Epic culmination where hero saves the day
- Celebration of complete journey
- Teaser for next adventure (math, science)

MILESTONES:
Define 5-7 key milestones tied to word count:
- Milestone 1: 5 words → "The First Spell Book"
- Milestone 2: 10 words → "The Crystal Cave"
- Milestone 3: 20 words → "The Dark Forest"
- etc.

Each milestone should:
- Unlock a story chapter for parent-child reading
- Grant protagonist a new ability/power/companion
- Feel earned and celebratory

OUTPUT FORMAT:
Return JSON with this structure:
{{
  "id": "epic_id",
  "title": "Epic Title",
  "theme": "{theme}",
  "total_chapters": 10,
  "acts": [
    {{
      "act_num": 1,
      "title": "Act Title",
      "description": "What happens in this act",
      "weeks": [1, 2, 3, 4, 5],
      "key_themes": ["theme1", "theme2"]
    }}
  ],
  "milestones": [
    {{
      "id": "milestone_1",
      "words_required": 5,
      "chapter_num": 1,
      "title": "The First Spell Book",
      "description": "Hero discovers ancient book with 5 glowing words",
      "reward": "Wizard's apprentice hat",
      "story_duration_minutes": 5
    }}
  ],
  "character_growth": {{
    "starting_state": "Curious but uncertain",
    "mid_journey": "Brave but struggling",
    "final_state": "Master of word magic"
  }},
  "narrative_arc": "Overall story arc description"
}}

Generate the epic arc now:"""
    
    async def _call_llm(self, prompt: str) -> str:
        """Call the LLM via OpenRouter."""
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": "You are a creative storyteller specializing in educational content for young children. You always respond with valid JSON."
                    },
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                temperature=0.8,  # Creative but not too random
                max_tokens=2000,
            )
            
            return response.choices[0].message.content
            
        except Exception as e:
            raise Exception(f"LLM call failed: {str(e)}")
    
    def _parse_story_response(
        self,
        response: str,
        word_spacing: Dict[str, List[int]]
    ) -> Dict[str, Any]:
        """Parse LLM response into structured story."""
        try:
            # Extract JSON from response (LLM might wrap it in markdown)
            json_start = response.find("{")
            json_end = response.rfind("}") + 1
            json_str = response[json_start:json_end]
            
            story = json.loads(json_str)
            
            # Validate story structure
            if "beats" not in story or "choice_points" not in story:
                raise ValueError("Missing required fields in story")
            
            # Ensure ID exists
            if "id" not in story:
                story["id"] = str(uuid.uuid4())
            
            return story
            
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to parse LLM response as JSON: {str(e)}")
        except Exception as e:
            raise ValueError(f"Story parsing failed: {str(e)}")
    
    def _parse_epic_response(self, response: str) -> Dict[str, Any]:
        """Parse LLM response into structured epic arc."""
        try:
            json_start = response.find("{")
            json_end = response.rfind("}") + 1
            json_str = response[json_start:json_end]
            
            epic = json.loads(json_str)
            
            # Validate epic structure
            required_fields = ["acts", "milestones", "character_growth"]
            for field in required_fields:
                if field not in epic:
                    raise ValueError(f"Missing required field: {field}")
            
            if "id" not in epic:
                epic["id"] = str(uuid.uuid4())
            
            return epic
            
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to parse epic response as JSON: {str(e)}")
        except Exception as e:
            raise ValueError(f"Epic parsing failed: {str(e)}")

