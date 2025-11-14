"""
Spaced Repetition Logic

Calculates optimal word placement in stories based on mastery levels
and spaced repetition principles.
"""
from enum import Enum
from typing import List, Tuple
import math


class SpacingStrategy(str, Enum):
    """Strategies for word spacing."""
    ADAPTIVE = "adaptive"  # Based on mastery level
    UNIFORM = "uniform"    # Evenly spaced
    FRONT_LOADED = "front_loaded"  # More at beginning
    CHALLENGING = "challenging"  # More at end


def calculate_word_spacing(
    word: str,
    mastery_level: float,
    num_beats: int = 12,
    strategy: SpacingStrategy = SpacingStrategy.ADAPTIVE
) -> List[int]:
    """
    Calculate optimal beat positions for a word to appear.
    
    Args:
        word: The word to practice
        mastery_level: 0.0-1.0 score (0=struggling, 1=mastered)
        num_beats: Total beats in the story
        strategy: Spacing strategy to use
        
    Returns:
        List of beat indices where word should appear
        
    Examples:
        >>> calculate_word_spacing("you", 0.9, 12)
        [0, 11]  # Mastered: beginning and end
        
        >>> calculate_word_spacing("her", 0.3, 12)
        [0, 3, 6, 9, 11]  # Struggling: frequent repetition
    """
    if strategy == SpacingStrategy.ADAPTIVE:
        return _adaptive_spacing(mastery_level, num_beats)
    elif strategy == SpacingStrategy.UNIFORM:
        return _uniform_spacing(num_beats)
    elif strategy == SpacingStrategy.FRONT_LOADED:
        return _front_loaded_spacing(num_beats)
    else:  # CHALLENGING
        return _challenging_spacing(num_beats)


def _adaptive_spacing(mastery_level: float, num_beats: int) -> List[int]:
    """
    Adaptive spacing based on mastery level.
    
    Mastery Level Guide:
    - 0.8-1.0: Mastered (2 repetitions - start & end)
    - 0.5-0.79: Learning (3 repetitions - start, middle, end)
    - 0.0-0.49: Struggling (5 repetitions - frequent)
    """
    if mastery_level >= 0.8:
        # Mastered: beginning and end for reinforcement
        return [0, num_beats - 1]
    
    elif mastery_level >= 0.5:
        # Learning: beginning, middle, end
        mid = num_beats // 2
        return [0, mid, num_beats - 1]
    
    else:
        # Struggling: frequent repetition with coaching
        # Positions at 0%, 25%, 50%, 75%, 100%
        positions = [
            0,
            num_beats // 4,
            num_beats // 2,
            (num_beats * 3) // 4,
            num_beats - 1
        ]
        # Remove duplicates and ensure all positions are valid
        return sorted(set(p for p in positions if 0 <= p < num_beats))


def _uniform_spacing(num_beats: int) -> List[int]:
    """Evenly spaced repetitions (3 times)."""
    if num_beats < 3:
        return list(range(num_beats))
    return [0, num_beats // 2, num_beats - 1]


def _front_loaded_spacing(num_beats: int) -> List[int]:
    """More repetitions early in the story."""
    positions = [0, num_beats // 4, num_beats // 2, num_beats - 1]
    return sorted(set(p for p in positions if 0 <= p < num_beats))


def _challenging_spacing(num_beats: int) -> List[int]:
    """More repetitions late in the story."""
    positions = [0, num_beats // 2, (num_beats * 3) // 4, num_beats - 1]
    return sorted(set(p for p in positions if 0 <= p < num_beats))


def calculate_spacing_for_all_words(
    words: List[Tuple[str, float]],
    num_beats: int = 12,
    strategy: SpacingStrategy = SpacingStrategy.ADAPTIVE
) -> dict:
    """
    Calculate spacing for multiple words.
    
    Args:
        words: List of (word, mastery_level) tuples
        num_beats: Total beats in story
        strategy: Spacing strategy
        
    Returns:
        Dict mapping words to their beat positions
        
    Example:
        >>> words = [("you", 0.9), ("see", 0.8), ("her", 0.3)]
        >>> calculate_spacing_for_all_words(words)
        {
            "you": [0, 11],
            "see": [0, 11],
            "her": [0, 3, 6, 9, 11]
        }
    """
    spacing = {}
    for word, mastery in words:
        spacing[word] = calculate_word_spacing(
            word=word,
            mastery_level=mastery,
            num_beats=num_beats,
            strategy=strategy
        )
    return spacing


def get_difficulty_distribution(words: List[Tuple[str, float]]) -> dict:
    """
    Analyze difficulty distribution of words.
    
    Returns counts of mastered/learning/struggling words
    to inform story pacing.
    """
    mastered = sum(1 for _, m in words if m >= 0.8)
    learning = sum(1 for _, m in words if 0.5 <= m < 0.8)
    struggling = sum(1 for _, m in words if m < 0.5)
    
    return {
        "mastered": mastered,
        "learning": learning,
        "struggling": struggling,
        "total": len(words),
        "avg_mastery": sum(m for _, m in words) / len(words) if words else 0.0
    }


def suggest_story_tone(words: List[Tuple[str, float]]) -> str:
    """
    Suggest story tone based on word difficulty.
    
    More struggling words → more supportive/coaching tone
    More mastered words → more celebratory tone
    """
    dist = get_difficulty_distribution(words)
    avg = dist["avg_mastery"]
    
    if avg >= 0.8:
        return "celebratory"
    elif avg >= 0.6:
        return "encouraging"
    elif avg >= 0.4:
        return "supportive"
    else:
        return "coaching"


if __name__ == "__main__":
    # Example usage
    print("Example: Mastered word")
    print(calculate_word_spacing("you", 0.9, 12))
    
    print("\nExample: Learning word")
    print(calculate_word_spacing("see", 0.6, 12))
    
    print("\nExample: Struggling word")
    print(calculate_word_spacing("her", 0.3, 12))
    
    print("\nExample: Multiple words")
    words = [("you", 0.9), ("see", 0.8), ("her", 0.3)]
    print(calculate_spacing_for_all_words(words))

