#!/usr/bin/env python3
"""
Generate a comprehensive homophone map for sight words using CMUdict.

This script:
1. Loads CMUdict (phonetic pronunciation dictionary)
2. For each sight word, finds all words with similar pronunciations
3. Generates a Dart map file for use in the Flutter app
4. Uses phonetic distance to find near-homophones (not just exact matches)
"""

import re
from collections import defaultdict
from typing import Dict, List, Set, Tuple
import urllib.request
import os

# Sight words from the app
SIGHT_WORDS = [
    'you', 'see', 'go', 'i', 'has', 'he', 'the', 'had', 'and', 'of',
    'a', 'we', 'is', 'am', 'at', 'to', 'as', 'have', 'in', 'it',
    'can', 'his', 'him', 'on', 'did', 'girl', 'for', 'but', 'up', 'all',
    'look', 'with', 'her', 'what', 'was', 'were', 'said', 'that', 'down', 'they',
    'boy', 'out', 'do', 'little', 'be', 'she', 'there', 'then', 'when', 'some',
    'red', 'orange', 'yellow', 'green', 'blue', 'purple', 'black', 'gray', 'pink',
    'white', 'brown'
]

def download_cmudict():
    """Download CMUdict if not present."""
    cmudict_path = 'cmudict.dict'
    if not os.path.exists(cmudict_path):
        print("Downloading CMUdict...")
        url = 'https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict'
        urllib.request.urlretrieve(url, cmudict_path)
        print(f"Downloaded to {cmudict_path}")
    return cmudict_path

def load_cmudict(filepath: str) -> Dict[str, List[str]]:
    """
    Load CMUdict and return a dictionary mapping words to pronunciations.
    
    Returns:
        Dict mapping lowercase word -> list of pronunciations (ARPAbet phonemes)
    """
    word_pronunciations = defaultdict(list)
    
    with open(filepath, 'r', encoding='latin-1') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(';;;'):
                continue
            
            # Format: WORD  PHONEME1 PHONEME2 ...
            # Or: WORD(N)  PHONEME1 PHONEME2 ... for alternate pronunciations
            parts = line.split()
            if len(parts) < 2:
                continue
            
            word = parts[0].lower()
            # Remove variant markers like (2), (3) etc.
            word = re.sub(r'\(\d+\)$', '', word)
            
            # Pronunciation is the rest (remove stress markers: 0,1,2)
            pronunciation = ' '.join(re.sub(r'\d', '', p) for p in parts[1:])
            word_pronunciations[word].append(pronunciation)
    
    return dict(word_pronunciations)

def phonetic_distance(phone1: str, phone2: str) -> int:
    """
    Calculate edit distance between two phoneme sequences.
    Lower = more similar.
    """
    words1 = phone1.split()
    words2 = phone2.split()
    
    # Simple Levenshtein distance
    if len(words1) < len(words2):
        words1, words2 = words2, words1
    
    if len(words2) == 0:
        return len(words1)
    
    previous_row = range(len(words2) + 1)
    for i, c1 in enumerate(words1):
        current_row = [i + 1]
        for j, c2 in enumerate(words2):
            # Cost of insertions, deletions, or substitutions
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    
    return previous_row[-1]

def find_homophones_and_near_homophones(
    sight_word: str,
    pronunciations_dict: Dict[str, List[str]],
    max_distance: int = 1
) -> Set[str]:
    """
    Find all words that sound the same or very similar to the sight word.
    
    Args:
        sight_word: The target sight word
        pronunciations_dict: CMUdict pronunciations
        max_distance: Maximum phonetic edit distance (0=exact, 1=one phoneme diff, etc.)
    
    Returns:
        Set of words that are homophones or near-homophones
    """
    if sight_word not in pronunciations_dict:
        print(f"Warning: '{sight_word}' not in CMUdict")
        return set()
    
    sight_pronunciations = pronunciations_dict[sight_word]
    homophones = set()
    
    # Check all words in dictionary
    for word, pronunciations in pronunciations_dict.items():
        if word == sight_word:
            continue
        
        # Check if any pronunciation of this word matches any pronunciation of sight word
        for word_pron in pronunciations:
            for sight_pron in sight_pronunciations:
                distance = phonetic_distance(word_pron, sight_pron)
                if distance <= max_distance:
                    homophones.add(word)
                    break
            if word in homophones:
                break
    
    return homophones

def filter_relevant_homophones(homophones: Set[str], sight_word: str) -> Set[str]:
    """
    Filter homophones to only keep relevant ones for speech recognition.
    
    Criteria:
    - Single words (no spaces, hyphens, special chars)
    - Reasonable length (not too long)
    - Common word patterns
    - Filter questionable single-letter mappings
    """
    # Single letters that are phonetically sound
    # These are clear phonetic matches to sight words
    good_single_letters = {
        'c': 'see',   # "c" sounds like "see"
        'b': 'be',    # "b" sounds like "be"
        'm': 'am',    # "m" sounds like "am" (partial)
        'n': 'in',    # "n" in "in" (user requested)
        'u': 'you',   # "u" sounds like "you"
        'q': 'you',   # "queue" sounds like "you"
        'y': 'i',     # "why" sounds like "i"
        'o': 'go',    # "oh" sounds like "go"
    }
    
    filtered = set()
    
    for word in homophones:
        # Must be simple alphanumeric
        if not re.match(r'^[a-z]+$', word):
            continue
        
        # Don't include words more than 3x the length of sight word
        if len(word) > len(sight_word) * 3 + 3:
            continue
        
        # For very short sight words (1-2 chars), only include short homophones
        if len(sight_word) <= 2 and len(word) > 4:
            continue
        
        # Filter single-letter mappings: only keep phonetically sound ones
        if len(word) == 1:
            # Only keep if it's in our approved list AND maps to the right word
            if word in good_single_letters and good_single_letters[word] == sight_word:
                filtered.add(word)
            # Special case: Don't map 'a' -> 'i' or 'i' -> 'a' (both are sight words)
            # This prevents confusion between two different sight words
            elif word in ['a', 'i'] and sight_word in ['a', 'i'] and word != sight_word:
                continue  # Skip this ambiguous mapping
            continue  # Skip all other single letters not in approved list
        
        filtered.add(word)
    
    return filtered

def generate_homophone_map() -> Dict[str, str]:
    """
    Generate complete homophone map for all sight words.
    
    Returns:
        Dict mapping homophone -> sight_word
    """
    print("Loading CMUdict...")
    cmudict_path = download_cmudict()
    pronunciations = load_cmudict(cmudict_path)
    
    print(f"Loaded {len(pronunciations)} words from CMUdict\n")
    
    homophone_map = {}
    
    for sight_word in SIGHT_WORDS:
        print(f"Processing '{sight_word}'...")
        
        # Find exact homophones (distance = 0)
        exact_homophones = find_homophones_and_near_homophones(
            sight_word, pronunciations, max_distance=0
        )
        exact_filtered = filter_relevant_homophones(exact_homophones, sight_word)
        
        # Find near-homophones (distance = 1)
        near_homophones = find_homophones_and_near_homophones(
            sight_word, pronunciations, max_distance=1
        )
        near_filtered = filter_relevant_homophones(near_homophones, sight_word)
        
        # Remove exact matches from near matches
        near_filtered -= exact_filtered
        
        print(f"  Exact homophones ({len(exact_filtered)}): {sorted(exact_filtered)}")
        print(f"  Near homophones ({len(near_filtered)}): {sorted(near_filtered)}")
        
        # Add to map
        for homophone in exact_filtered:
            homophone_map[homophone] = sight_word
        
        # Add near-homophones (these might be more conservative)
        for homophone in near_filtered:
            # Only add if not already mapped to another sight word
            if homophone not in homophone_map:
                homophone_map[homophone] = sight_word
        
        print()
    
    # Manual overrides for specific cases not well-captured by CMUdict
    # These are based on observed recognition patterns
    manual_overrides = {
        'oh': 'all',  # User requested: children often say "oh" for "all"
    }
    
    print("Adding manual overrides...")
    for homophone, sight_word in manual_overrides.items():
        if homophone in homophone_map and homophone_map[homophone] != sight_word:
            print(f"  WARNING: Overriding '{homophone}': '{homophone_map[homophone]}' -> '{sight_word}'")
        else:
            print(f"  Adding: '{homophone}' -> '{sight_word}'")
        homophone_map[homophone] = sight_word
    print()
    
    return homophone_map

def generate_dart_file(homophone_map: Dict[str, str], output_path: str):
    """Generate Dart file with homophone map."""
    
    # Sort by target word, then by source word
    sorted_items = sorted(homophone_map.items(), key=lambda x: (x[1], x[0]))
    
    dart_code = '''// AUTO-GENERATED FILE - DO NOT EDIT
// Generated by asset-generation/tools/generate_homophone_map.py
// 
// This file contains a comprehensive homophone and near-homophone map
// for sight word speech recognition. Generated from CMUdict phonetic dictionary.

/// Maps homophones and phonetically similar words to their target sight words.
/// 
/// This map is used by the speech recognizer to handle common misrecognitions
/// where the ASR model returns a word that sounds the same or very similar
/// to the expected sight word.
/// 
/// Examples:
/// - "aye" -> "i" (exact homophone)
/// - "sea" -> "see" (exact homophone)
/// - "wear" -> "were" (near homophone, 1 phoneme difference)
const Map<String, String> sightWordHomophoneMap = {
'''
    
    # Group by target sight word for better readability
    current_target = None
    for source, target in sorted_items:
        if target != current_target:
            if current_target is not None:
                dart_code += '\n'
            dart_code += f'  // Homophones for "{target}"\n'
            current_target = target
        
        dart_code += f"  '{source}': '{target}',\n"
    
    dart_code += '};\n'
    
    with open(output_path, 'w') as f:
        f.write(dart_code)
    
    print(f"Generated Dart file: {output_path}")
    print(f"Total homophone mappings: {len(homophone_map)}")

def main():
    print("=" * 60)
    print("Generating Homophone Map for Sight Words")
    print("=" * 60)
    print()
    
    homophone_map = generate_homophone_map()
    
    print("=" * 60)
    print(f"Generated {len(homophone_map)} total homophone mappings")
    print("=" * 60)
    print()
    
    # Generate Dart file in lib/services/
    output_path = os.path.join(
        os.path.dirname(__file__),
        '../../lib/services/sight_word_homophones.dart'
    )
    
    generate_dart_file(homophone_map, output_path)
    
    print("\nDone! You can now import this in sherpa_recognizer.dart")
    print("and replace the static _homonymMap with the generated map.")

if __name__ == '__main__':
    main()

