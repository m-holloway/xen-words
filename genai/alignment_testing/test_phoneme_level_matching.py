#!/usr/bin/env python3
"""
PHONEME-LEVEL Matching Test

This tests phoneme-level fuzzy matching instead of word-level.
Should achieve >85% accuracy vs 50% with word-level.
"""

import sys
sys.path.append('.')
from test_phonetic_matching import (
    CMU_DICT, word_to_phonemes, VOWELS
)
from typing import List, Tuple

def text_to_phoneme_sequence(text: str) -> Tuple[List[str], List[int]]:
    """
    Convert text to phoneme sequence with word boundaries.
    
    Returns: (phonemes, word_boundaries)
    - phonemes: Flat list of all phonemes
    - word_boundaries: Indices where each word starts
    """
    words = text.lower().split()
    phonemes = []
    boundaries = [0]
    
    for word in words:
        word_phonemes = word_to_phonemes(word)
        phonemes.extend(word_phonemes)
        boundaries.append(len(phonemes))
    
    return phonemes, boundaries[:-1]  # Don't include final boundary

def phoneme_similarity(p1: str, p2: str) -> float:
    """
    Calculate similarity between two phonemes.
    
    Returns:
    - 1.0: exact match
    - 0.8-0.9: similar phonemes (same class)
    - 0.5-0.7: moderate similarity
    - <0.5: different
    """
    if p1 == p2:
        return 1.0
    
    # Phoneme classes
    vowels = set(VOWELS)
    stops = {'P', 'B', 'T', 'D', 'K', 'G'}
    fricatives = {'F', 'V', 'TH', 'DH', 'S', 'Z', 'SH', 'ZH', 'HH'}
    nasals = {'M', 'N', 'NG'}
    liquids = {'L', 'R'}
    semivowels = {'W', 'Y'}
    
    # Same class = high similarity
    if p1 in vowels and p2 in vowels:
        return 0.75  # All vowels somewhat similar
    elif p1 in stops and p2 in stops:
        # Voiced/voiceless pairs
        if (p1, p2) in [('P', 'B'), ('B', 'P'), ('T', 'D'), ('D', 'T'), ('K', 'G'), ('G', 'K')]:
            return 0.9
        return 0.8
    elif p1 in fricatives and p2 in fricatives:
        if (p1, p2) in [('F', 'V'), ('V', 'F'), ('S', 'Z'), ('Z', 'S'), ('TH', 'DH'), ('DH', 'TH')]:
            return 0.9
        return 0.8
    elif p1 in nasals and p2 in nasals:
        return 0.85
    elif p1 in liquids and p2 in liquids:
        return 0.9  # L and R very similar
    elif p1 in semivowels and p2 in semivowels:
        return 0.85
    
    # Moderate similarity if related
    if (p1 in vowels and p2 in semivowels) or (p2 in vowels and p1 in semivowels):
        return 0.6
    
    return 0.3  # Very different

def fuzzy_phoneme_align(
    detected_phonemes: List[str],
    script_phonemes: List[str],
    word_boundaries: List[int],
    start_word: int = 0,
    window_size: int = 15
) -> Tuple[int, float]:
    """
    Align detected phonemes to script using fuzzy matching.
    
    Args:
        detected_phonemes: Phonemes from STT output
        script_phonemes: Expected phonemes from script
        word_boundaries: Where each word starts in script_phonemes
        start_word: Current word index to start search
        window_size: How many recent phonemes to consider
    
    Returns: (current_word_index, confidence)
    """
    if not detected_phonemes:
        return start_word, 0.0
    
    # Only look at recent phonemes (sliding window)
    recent_detected = detected_phonemes[-window_size:]
    
    # Start search from current word position
    start_phoneme_idx = word_boundaries[start_word] if start_word < len(word_boundaries) else 0
    
    best_word_idx = start_word
    best_score = 0.0
    
    # Try aligning at each possible position
    for word_idx in range(start_word, min(start_word + 10, len(word_boundaries))):
        script_start = word_boundaries[word_idx]
        
        # Score this alignment
        score, end_phoneme = _score_phoneme_alignment(
            recent_detected,
            script_phonemes,
            script_start
        )
        
        if score > best_score:
            best_score = score
            # Find which word this phoneme position corresponds to
            for i in range(len(word_boundaries) - 1, -1, -1):
                if end_phoneme >= word_boundaries[i]:
                    best_word_idx = i
                    break
    
    return best_word_idx, best_score

def _score_phoneme_alignment(
    detected: List[str],
    script: List[str],
    script_start: int
) -> Tuple[float, int]:
    """
    Score how well detected phonemes match script starting at position.
    
    Returns: (score, ending_phoneme_index)
    """
    total_score = 0.0
    detected_idx = 0
    script_idx = script_start
    last_script_idx = script_start
    
    while detected_idx < len(detected) and script_idx < len(script):
        det_phoneme = detected[detected_idx]
        script_phoneme = script[script_idx]
        
        similarity = phoneme_similarity(det_phoneme, script_phoneme)
        
        if similarity > 0.7:
            # Good match, advance both
            total_score += similarity
            last_script_idx = script_idx
            detected_idx += 1
            script_idx += 1
        elif similarity > 0.5:
            # Moderate match, advance with lower confidence
            total_score += similarity * 0.8
            last_script_idx = script_idx
            detected_idx += 1
            script_idx += 1
        elif detected_idx + 1 < len(detected):
            # Try skipping detected phoneme (insertion error)
            next_similarity = phoneme_similarity(detected[detected_idx + 1], script_phoneme)
            if next_similarity > similarity:
                # Next phoneme is better match, skip current
                detected_idx += 1
            else:
                # Try skipping script phoneme (deletion error)
                if script_idx + 1 < len(script):
                    next_script_sim = phoneme_similarity(det_phoneme, script[script_idx + 1])
                    if next_script_sim > similarity:
                        script_idx += 1
                    else:
                        # No good match, skip detected
                        detected_idx += 1
                else:
                    detected_idx += 1
        else:
            # At end, just skip
            detected_idx += 1
    
    # Normalize by number of detected phonemes
    avg_score = total_score / len(detected) if detected else 0.0
    
    return avg_score, last_script_idx

# ============================================================
# TEST CASES
# ============================================================

def test_phoneme_scenario(name: str, script: str, detected: str, expected_word: int):
    """Test phoneme-level tracking."""
    print(f"\n{'='*60}")
    print(f"📋 {name}")
    print(f"{'='*60}")
    
    script_words = script.lower().split()
    
    # Convert to phonemes
    script_phonemes, word_boundaries = text_to_phoneme_sequence(script)
    detected_phonemes, _ = text_to_phoneme_sequence(detected)
    
    print(f"\n📜 Script:   \"{script}\"")
    print(f"   Words: {script_words}")
    print(f"   Phonemes: {script_phonemes}")
    print(f"   Boundaries: {word_boundaries}")
    
    print(f"\n🎤 Detected: \"{detected}\"")
    print(f"   Phonemes: {detected_phonemes}")
    
    print(f"\n🎯 Expected: word {expected_word} (\"{script_words[expected_word]}\")")
    
    # Align
    word_idx, confidence = fuzzy_phoneme_align(
        detected_phonemes,
        script_phonemes,
        word_boundaries,
        start_word=0,
        window_size=20
    )
    
    print(f"\n📊 Result:")
    print(f"   Position: word {word_idx} (\"{script_words[word_idx]}\")")
    print(f"   Confidence: {confidence:.2f}")
    
    # Verdict
    correct = word_idx == expected_word
    if correct:
        if confidence > 0.7:
            print(f"   ✅ CORRECT with HIGH confidence!")
        elif confidence > 0.5:
            print(f"   ✅ CORRECT with MODERATE confidence")
        else:
            print(f"   ✅ CORRECT but LOW confidence")
    else:
        off_by = abs(word_idx - expected_word)
        if off_by == 1:
            print(f"   ⚠️  CLOSE (off by 1 word)")
        else:
            print(f"   ❌ WRONG (off by {off_by} words)")
    
    return correct

def main():
    print("=" * 60)
    print("🧪 PHONEME-LEVEL MATCHING TEST SUITE")
    print("=" * 60)
    print("\nTesting PHONEME-level (not word-level) alignment...")
    print("Expected: >85% accuracy (vs 50% with word-level)")
    
    script = "you are adalyn today you see a glowing window shimmering in your backyard"
    
    results = []
    
    # Test 1: Perfect
    results.append(test_phoneme_scenario(
        "Test 1: Perfect Recognition",
        script,
        "you are adalyn today",
        expected_word=3  # "today"
    ))
    
    # Test 2: Split word (THIS SHOULD NOW PASS!)
    results.append(test_phoneme_scenario(
        "Test 2: Split Word (ad a lyn)",
        script,
        "you are ad a lyn today",
        expected_word=3  # "today"
    ))
    
    # Test 3: STT mishear (SHOULD BE BETTER!)
    results.append(test_phoneme_scenario(
        "Test 3: STT Mishear (add lynn)",
        script,
        "you are add lynn today",
        expected_word=3  # "today"
    ))
    
    # Test 4: Extra noise word
    results.append(test_phoneme_scenario(
        "Test 4: Extra Noise Word",
        script,
        "you the are adalyn",
        expected_word=2  # "adalyn"
    ))
    
    # Test 5: Longer sequence
    results.append(test_phoneme_scenario(
        "Test 5: Longer Sequence",
        script,
        "today you see a glowing window",
        expected_word=8  # "window"
    ))
    
    # Test 6: Multiple words
    results.append(test_phoneme_scenario(
        "Test 6: Multiple Words",
        script,
        "you are adalyn today you see",
        expected_word=5  # "see"
    ))
    
    # Summary
    print(f"\n" + "=" * 60)
    print(f"📊 SUMMARY")
    print(f"=" * 60)
    passed = sum(results)
    total = len(results)
    print(f"\nPassed: {passed}/{total} ({100*passed/total:.0f}%)")
    
    print(f"\n🎯 COMPARISON:")
    print(f"   Word-level matching:   50% (3/6 passed)")
    print(f"   Phoneme-level matching: {100*passed/total:.0f}% ({passed}/{total} passed)")
    
    if passed >= total * 0.85:
        print(f"\n✅ EXCELLENT! >85% accuracy achieved!")
        print(f"   Phoneme-level matching is production-ready!")
    elif passed >= total * 0.7:
        print(f"\n⚠️  GOOD: >70% accuracy")
        print(f"   With tuning, can reach >85%")
    else:
        print(f"\n⚠️  Needs more work")
    
    print(f"\n💡 Next Steps:")
    if passed >= total * 0.85:
        print(f"   1. Port to Dart")
        print(f"   2. Integrate with Sherpa-ONNX")
        print(f"   3. Test on real parent reading audio")
    else:
        print(f"   1. Tune phoneme similarity scores")
        print(f"   2. Adjust window size")
        print(f"   3. Add more phoneme classes")

if __name__ == "__main__":
    main()

