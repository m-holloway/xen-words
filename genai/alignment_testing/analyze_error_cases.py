#!/usr/bin/env python3
"""
Error Case Analysis

Analyzes specific cases where our phoneme alignment failed
to understand what went wrong and how to improve it.
"""

import json
import sys
from pathlib import Path

sys.path.append('.')
from test_phonetic_matching import word_to_phonemes

def analyze_mismatches():
    """
    Analyze the specific error cases from our CLI test.
    
    From the test we saw 92.3% accuracy (12/13 correct within ±1 word).
    Let's look at what went wrong in that 1 failure.
    """
    
    # Load ground truth
    with open('clean_recording_gt.json') as f:
        gt = json.load(f)
    
    gt_text = ' '.join([w['word'] for w in gt['words']])
    
    # Sherpa output from our test
    sherpa_text = "YOU ARE ADELAN AND TO DAY YOU WENT TO SEE A GLOWING TRAIL OUTSIDE YOUR WINDOW YOU PUT ON YOUR RAINBOW BOOTS AND OPEN THE DOOR THE SPARKLING PATH LEADS TO A BIG TREE YOU FOLLOW IT AND FIND A LITTLE FAIRY SHE IS SITTING ON A FLOWER THE FAIRY LOOKS AT YOU AND SMILES SHE HAS MAGIC DUST IN HER HANDS"
    
    # Script
    with open('scripts/adalyn_story.txt') as f:
        script = ' '.join(f.read().strip().split())
    
    print("="*60)
    print("🔍 ERROR CASE ANALYSIS")
    print("="*60)
    
    print(f"\n📜 Expected (Script):")
    print(f"   \"{script[:100]}...\"")
    
    print(f"\n🎤 Ground Truth (Whisper):")
    print(f"   \"{gt_text[:100]}...\"")
    
    print(f"\n🤖 Detected (Sherpa):")
    print(f"   \"{sherpa_text[:100]}...\"")
    
    # Convert to phonemes
    def text_to_phonemes(text):
        words = text.lower().split()
        phonemes = []
        boundaries = [0]
        for word in words:
            ph = word_to_phonemes(word)
            phonemes.extend(ph)
            boundaries.append(len(phonemes))
        return phonemes, boundaries[:-1], words
    
    script_ph, script_bounds, script_words = text_to_phonemes(script)
    sherpa_ph, sherpa_bounds, sherpa_words = text_to_phonemes(sherpa_text)
    gt_ph, gt_bounds, gt_words = text_to_phonemes(gt_text)
    
    print(f"\n📊 Phoneme Stats:")
    print(f"   Script: {len(script_words)} words, {len(script_ph)} phonemes")
    print(f"   Whisper: {len(gt_words)} words, {len(gt_ph)} phonemes")
    print(f"   Sherpa: {len(sherpa_words)} words, {len(sherpa_ph)} phonemes")
    
    # Find specific mismatches
    print(f"\n🔍 Word-by-Word Comparison:")
    print(f"   (First 20 words)")
    print(f"\n   {'Idx':<4} {'Script':<20} {'Sherpa':<20} {'Match':<6}")
    print(f"   {'-'*54}")
    
    for i in range(min(20, len(script_words))):
        script_word = script_words[i] if i < len(script_words) else '???'
        sherpa_word = sherpa_words[i] if i < len(sherpa_words) else '???'
        match = '✅' if script_word.lower() == sherpa_word.lower() else '❌'
        
        print(f"   {i:<4} {script_word:<20} {sherpa_word:<20} {match}")
    
    # Identify problem areas
    print(f"\n🎯 Key Issues Identified:")
    
    issues = []
    
    # Issue 1: "Adalyn" -> "ADELAN"
    if 'adalyn' in script_words and 'adelan' in sherpa_words:
        issues.append({
            'type': 'name_mispronunciation',
            'expected': 'Adalyn',
            'detected': 'ADELAN',
            'expected_ph': word_to_phonemes('adalyn'),
            'detected_ph': word_to_phonemes('adelan'),
            'description': 'Name mispronunciation (missing final syllable)'
        })
    
    # Issue 2: "today" -> "TO DAY"
    script_today_idx = [i for i, w in enumerate(script_words) if w.lower() == 'today']
    sherpa_to_idx = [i for i, w in enumerate(sherpa_words) if w.lower() == 'to']
    if script_today_idx and len(sherpa_to_idx) > 1:
        issues.append({
            'type': 'word_split',
            'expected': 'today',
            'detected': 'TO DAY',
            'expected_ph': word_to_phonemes('today'),
            'detected_ph': word_to_phonemes('to') + word_to_phonemes('day'),
            'description': 'Single word split into two'
        })
    
    for i, issue in enumerate(issues, 1):
        print(f"\n   Issue {i}: {issue['type']}")
        print(f"   Expected: \"{issue['expected']}\"")
        print(f"   Detected: \"{issue['detected']}\"")
        print(f"   Expected phonemes: {issue['expected_ph']}")
        print(f"   Detected phonemes: {issue['detected_ph']}")
        print(f"   Description: {issue['description']}")
        
        # Calculate phoneme overlap
        exp_set = set(issue['expected_ph'])
        det_set = set(issue['detected_ph'])
        overlap = len(exp_set & det_set) / max(len(exp_set), len(det_set))
        print(f"   Phoneme overlap: {100*overlap:.1f}%")
    
    print(f"\n💡 Insights:")
    print(f"   1. Names are hard (Adalyn → ADELAN)")
    print(f"   2. Word boundaries ambiguous (today → to day)")
    print(f"   3. But phoneme content is mostly there!")
    print(f"   4. Need SEQUENCE-aware fuzzy matching")
    
    return issues

def demonstrate_sequence_matching():
    """
    Show how sequence-aware matching could help.
    """
    print(f"\n{'='*60}")
    print(f"🎯 SEQUENCE MATCHING POTENTIAL")
    print(f"{'='*60}\n")
    
    # Example: "Adalyn" vs "ADELAN"
    expected = word_to_phonemes('adalyn')
    detected = word_to_phonemes('adelan')
    
    print(f"Example 1: Name mispronunciation")
    print(f"   Expected: 'Adalyn' = {expected}")
    print(f"   Detected: 'ADELAN' = {detected}")
    
    # Simple exact match: fails
    exact_match = expected == detected
    print(f"\n   Exact match: {exact_match} ❌")
    
    # Our current phoneme-by-phoneme: how many match?
    matches = sum(1 for e, d in zip(expected, detected) if e == d)
    accuracy = matches / max(len(expected), len(detected))
    print(f"   Current approach: {matches}/{max(len(expected), len(detected))} phonemes = {100*accuracy:.1f}%")
    
    # Sequence alignment (Levenshtein): what's the edit distance?
    def levenshtein(s1, s2):
        if len(s1) < len(s2):
            return levenshtein(s2, s1)
        if len(s2) == 0:
            return len(s1)
        
        previous = range(len(s2) + 1)
        for i, c1 in enumerate(s1):
            current = [i + 1]
            for j, c2 in enumerate(s2):
                insertions = previous[j + 1] + 1
                deletions = current[j] + 1
                substitutions = previous[j] + (c1 != c2)
                current.append(min(insertions, deletions, substitutions))
            previous = current
        
        return previous[-1]
    
    edit_dist = levenshtein(expected, detected)
    max_len = max(len(expected), len(detected))
    similarity = 1 - (edit_dist / max_len)
    
    print(f"   Sequence alignment: edit distance = {edit_dist}, similarity = {100*similarity:.1f}% ✅")
    
    # Example 2: "today" vs "to" + "day"
    print(f"\nExample 2: Word split")
    expected2 = word_to_phonemes('today')
    detected2 = word_to_phonemes('to') + word_to_phonemes('day')
    
    print(f"   Expected: 'today' = {expected2}")
    print(f"   Detected: 'to' + 'day' = {detected2}")
    
    exact_match2 = expected2 == detected2
    print(f"\n   Exact match: {exact_match2}")
    
    matches2 = sum(1 for e, d in zip(expected2, detected2) if e == d)
    accuracy2 = matches2 / max(len(expected2), len(detected2))
    print(f"   Current approach: {matches2}/{max(len(expected2), len(detected2))} phonemes = {100*accuracy2:.1f}%")
    
    edit_dist2 = levenshtein(expected2, detected2)
    similarity2 = 1 - (edit_dist2 / max(len(expected2), len(detected2)))
    print(f"   Sequence alignment: edit distance = {edit_dist2}, similarity = {100*similarity2:.1f}% ✅")
    
    print(f"\n💡 Key Insight:")
    print(f"   Sequence-aware matching (Levenshtein, DTW, etc.) can handle:")
    print(f"   - Insertions (extra phonemes)")
    print(f"   - Deletions (missing phonemes)")
    print(f"   - Substitutions (similar phonemes)")
    print(f"   - Out-of-order matches")
    print(f"\n   This should get us to 95-99% accuracy! 🎯")

if __name__ == "__main__":
    issues = analyze_mismatches()
    demonstrate_sequence_matching()

