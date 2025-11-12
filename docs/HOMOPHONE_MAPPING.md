# Comprehensive Homophone Mapping System

## Overview

This document describes the phonetic homophone mapping system used to improve sight word recognition accuracy in the Xen Words app.

## Problem Statement

Speech recognition models (like Sherpa ONNX) often return words that sound **very similar** to the target sight word, but aren't exact matches. For example, when a child says "were", the model might return:

- "where" (exact homophone)
- "wear" (near homophone, 1 phoneme difference)
- "wire" (near homophone)
- "word" (near homophone)
- "work" (near homophone)

Previously, we had a manually curated map with only ~20 entries, missing many common confusions.

## Solution

We pre-computed a comprehensive homophone map using the **CMUdict phonetic dictionary** (Carnegie Mellon University's pronouncing dictionary). This dictionary contains phonetic transcriptions for over 126,000 English words.

### How It Works

1. **Phonetic Analysis**: For each of the 61 sight words, we:
   - Extract all pronunciation variants from CMUdict
   - Calculate phonetic edit distance to all other words in the dictionary
   - Identify exact homophones (distance = 0) and near-homophones (distance = 1)

2. **Filtering**: We filter results to only include relevant words:
   - Simple alphanumeric words only
   - Reasonable length (not more than 3x the sight word length + 3)
   - For very short sight words, only short homophones

3. **Map Generation**: Create a Dart map file with all mappings

### Results

The system generated **3,534 homophone mappings** covering all 61 sight words:

#### Example: "were" (116 mappings)
```dart
'schwer': 'were',
'swor': 'were',
'waugh': 'were',
'weier': 'were',
'weigh': 'were',
'wire': 'were',
'word': 'were',
'work': 'were',
'worm': 'were',
'worry': 'were',
'worse': 'were',
// ... and 105 more
```

#### Example: "see" (8 exact + 197 near homophones)
```dart
'c': 'see',          // exact homophone
'sea': 'see',        // exact homophone
'sci': 'see',        // exact homophone
'si': 'see',         // exact homophone
// plus 197 near-homophones
```

## Implementation

### Files

1. **Generator Script**: `asset-generation/tools/generate_homophone_map.py`
   - Downloads CMUdict if not present
   - Computes phonetic distances
   - Generates Dart file

2. **Generated Map**: `lib/services/sight_word_homophones.dart`
   - Auto-generated (do not edit manually)
   - Contains the comprehensive homophone map

3. **Integration**: `lib/services/sherpa_recognizer.dart`
   - Imports and uses the generated map
   - Applies homophone correction during recognition

### How Recognition Works

When the speech recognizer receives a result:

1. **Direct Match**: Check if the recognized text exactly matches a sight word
2. **Token Analysis**: Analyze BPE tokens from the model
3. **Homophone Correction**: For each recognized word/token:
   ```dart
   final corrected = _applyHomonymCorrection(recognizedWord);
   if (corrected != null && _sightWords.contains(corrected)) {
     // Match found via homophone!
     return corrected;
   }
   ```
4. **Context-Aware**: Prioritize matches for the expected word (if known)

### Usage Example

```dart
// Before (manual map):
_homonymMap = {
  'aye': 'i',
  'sea': 'see',
  // only ~20 entries
}

// After (generated map):
_homonymMap = sightWordHomophoneMap;
// 3,534 entries covering all phonetic variations!
```

## Regenerating the Map

If you add new sight words or want to adjust the phonetic distance threshold:

```bash
cd asset-generation/tools
python3 generate_homophone_map.py
```

This will:
1. Download CMUdict (if needed)
2. Analyze all sight words
3. Generate new `lib/services/sight_word_homophones.dart`
4. Print statistics about mappings found

### Customization

In `generate_homophone_map.py`, you can adjust:

- **`max_distance`**: Phonetic edit distance threshold (default: 0 for exact, 1 for near)
  ```python
  exact_homophones = find_homophones_and_near_homophones(
      sight_word, pronunciations, max_distance=0
  )
  near_homophones = find_homophones_and_near_homophones(
      sight_word, pronunciations, max_distance=1
  )
  ```

- **Filtering Rules**: In `filter_relevant_homophones()`:
  ```python
  # Length constraint
  if len(word) > len(sight_word) * 3 + 3:
      continue
  
  # Short word constraint  
  if len(sight_word) <= 2 and len(word) > 4:
      continue
  ```

## Benefits

1. **Comprehensive Coverage**: 3,534 mappings vs. ~20 manual entries
2. **Phonetically Accurate**: Based on actual pronunciation data, not guesswork
3. **Maintainable**: Regenerate automatically when sight words change
4. **Robust**: Handles all common ASR misrecognitions for similar-sounding words
5. **No Performance Impact**: Pre-computed at build time, constant-time lookup at runtime

## Technical Details

### Phonetic Distance

The system uses **Levenshtein edit distance** on phoneme sequences:

```
"were" → /W EH R/
"wear" → /W EH R/  (distance = 0, exact homophone)
"wire" → /W AY R/  (distance = 1, near homophone: EH vs AY)
```

### BPE Token Handling

Sherpa ONNX uses Byte Pair Encoding (BPE), which splits words into subword units:

```
tokens.txt:
▁WERE 130    (word boundary + "WERE")
▁WE 98       (word boundary + "WE")
RE 26        (subword unit "RE")
```

The recognizer:
1. Reconstructs full words from BPE tokens
2. Applies homophone mapping to reconstructed words
3. Checks individual tokens as fallback

### Memory Usage

The generated map is a compile-time constant:
- **Size**: ~3,534 entries × ~20 bytes = ~70 KB
- **Impact**: Negligible on modern devices
- **Lookup**: O(1) hash table lookup

## Future Improvements

1. **Distance-Based Scoring**: Use phonetic distance as confidence score
2. **Context-Aware Filtering**: Weight homophones based on word frequency
3. **Regional Variants**: Add support for different English accents
4. **User Feedback**: Learn which homophones are most problematic for users
5. **Fuzzy Matching**: Combine with edit distance for even more robustness

## References

- **CMUdict**: https://github.com/cmusphinx/cmudict
- **ARPAbet Phonemes**: https://en.wikipedia.org/wiki/ARPABET
- **Levenshtein Distance**: https://en.wikipedia.org/wiki/Levenshtein_distance
- **BPE Encoding**: https://arxiv.org/abs/1508.07909

## Troubleshooting

### "Word X not found in CMUdict"

Some proper nouns or very rare words might not be in CMUdict. In that case, the script will print a warning and skip that word. You can either:
- Remove that word from the sight word list
- Manually add phonetic homophones to the generated file

### Generated map is too large

Reduce `max_distance` from 1 to 0 (exact homophones only):

```python
# Only use exact homophones
near_homophones = find_homophones_and_near_homophones(
    sight_word, pronunciations, max_distance=0  # was 1
)
```

### Too many false positives

Tighten the filtering rules in `filter_relevant_homophones()`:

```python
# More strict length constraint
if len(word) > len(sight_word) * 2 + 2:  # was 3 + 3
    continue
```

