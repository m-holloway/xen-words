"""
Story Generation API

FastAPI service for generating personalized, LLM-powered stories
with spaced repetition word placement.
"""
import os
import json
from typing import List, Dict, Any, Optional
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import openai

from .spaced_repetition import calculate_word_spacing, SpacingStrategy
from .story_generator import StoryGenerator

# Initialize FastAPI
app = FastAPI(
    title="Xen Words Story Generator",
    description="LLM-powered story generation with spaced repetition",
    version="1.0.0"
)

# CORS middleware for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify Flutter app URL
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize OpenAI client for OpenRouter
openai_client = openai.OpenAI(
    api_key=os.getenv("OPENROUTER_API_KEY"),
    base_url="https://openrouter.ai/api/v1"
)

# Initialize story generator
story_generator = StoryGenerator(openai_client)


# ============================================================================
# Request/Response Models
# ============================================================================

class TargetWord(BaseModel):
    """A word to practice in the story."""
    word: str
    mastery_level: float = Field(ge=0.0, le=1.0, description="0.0-1.0 mastery score")


class StoryRequest(BaseModel):
    """Request to generate a story."""
    child_name: str
    protagonist_name: Optional[str] = None  # Defaults to child_name
    age: int = Field(ge=3, le=10)
    theme: str = "adventure"
    target_words: List[TargetWord]
    chapter_num: int = 1
    total_chapters: int = 10
    num_choices: int = Field(default=2, ge=0, le=3)
    epic_context: Optional[str] = None  # Overall arc summary
    

class EpicRequest(BaseModel):
    """Request to generate an epic arc structure."""
    child_name: str
    protagonist_name: Optional[str] = None
    age: int = Field(ge=3, le=10)
    theme: str = "adventure"
    total_weeks: int = 25
    total_words: int = 100


class StoryBeat(BaseModel):
    """A single beat in the story."""
    type: str  # narration, child_turn, coach_intervention, celebration
    text: str
    speaker: Optional[str] = None  # parent, coach, child
    target_words: List[str] = []
    coach_phrase: Optional[str] = None


class StoryChoice(BaseModel):
    """A choice point for the child."""
    id: str
    prompt_text: str
    preview_text: str
    choice_text: str


class ChoicePoint(BaseModel):
    """A point in the story where child makes a choice."""
    id: str
    prompt_text: str
    choices: List[StoryChoice]


class StoryResponse(BaseModel):
    """Generated story chapter."""
    id: str
    title: str
    beats: List[StoryBeat]
    choice_points: List[ChoicePoint]
    metadata: Dict[str, Any]


# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": "story_generator",
        "version": "1.0.0"
    }


@app.post("/generate-story", response_model=StoryResponse)
async def generate_story(request: StoryRequest):
    """
    Generate a single story chapter with target words.
    
    Uses LLM to create a narrative that naturally incorporates
    the target words at optimal spacing intervals based on mastery levels.
    """
    try:
        # Use protagonist name or default to child name
        protagonist = request.protagonist_name or request.child_name
        
        # Generate the story
        story = await story_generator.generate_chapter(
            child_name=request.child_name,
            protagonist_name=protagonist,
            age=request.age,
            theme=request.theme,
            target_words=[(w.word, w.mastery_level) for w in request.target_words],
            chapter_num=request.chapter_num,
            total_chapters=request.total_chapters,
            num_choices=request.num_choices,
            epic_context=request.epic_context,
        )
        
        return story
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Story generation failed: {str(e)}")


@app.post("/generate-epic")
async def generate_epic(request: EpicRequest):
    """
    Generate an epic arc structure for the entire learning journey.
    
    Returns a high-level outline of the multi-chapter story arc
    with milestones tied to word mastery groups.
    """
    try:
        protagonist = request.protagonist_name or request.child_name
        
        epic = await story_generator.generate_epic_arc(
            child_name=request.child_name,
            protagonist_name=protagonist,
            age=request.age,
            theme=request.theme,
            total_weeks=request.total_weeks,
            total_words=request.total_words,
        )
        
        return epic
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Epic generation failed: {str(e)}")


@app.post("/calculate-spacing")
async def calculate_spacing(
    words: List[TargetWord],
    num_beats: int = 12,
    strategy: SpacingStrategy = SpacingStrategy.ADAPTIVE
):
    """
    Calculate optimal spacing for words in a story.
    
    Returns beat positions where each word should appear
    based on mastery levels and spaced repetition principles.
    """
    try:
        spacing = {}
        for word in words:
            positions = calculate_word_spacing(
                word=word.word,
                mastery_level=word.mastery_level,
                num_beats=num_beats,
                strategy=strategy
            )
            spacing[word.word] = positions
            
        return {
            "spacing": spacing,
            "num_beats": num_beats,
            "strategy": strategy.value
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Spacing calculation failed: {str(e)}")


@app.get("/themes")
async def list_themes():
    """List available story themes."""
    return {
        "themes": [
            {"id": "adventure", "name": "Adventure", "description": "Exciting quests and exploration"},
            {"id": "magic", "name": "Magic", "description": "Wizards, spells, and enchantments"},
            {"id": "space", "name": "Space", "description": "Rockets, planets, and aliens"},
            {"id": "ocean", "name": "Ocean", "description": "Underwater adventures with sea creatures"},
            {"id": "forest", "name": "Forest", "description": "Woodland creatures and nature magic"},
            {"id": "castle", "name": "Castle", "description": "Knights, dragons, and princesses"},
            {"id": "friendship", "name": "Friendship", "description": "Making friends and helping others"},
            {"id": "mystery", "name": "Mystery", "description": "Solving puzzles and uncovering secrets"},
        ]
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)

