# Homophone Map Cleanup Summary

## Problem Identified

The initial CMUdict-generated homophone map included **24 single-letter mappings**, many of which were phonetically questionable and could cause false positives. Additionally, there was partial matching logic in the code that could match parts of words, also causing false positives.

## Changes Made

### 1. Removed Questionable Single-Letter Mappings

**Before:** 24 single-letter mappings (many questionable)

**Removed (17 problematic mappings):**
```
'd' -> 'see'    # Not phonetically clear
'e' -> 'see'    # Not phonetically clear
'f' -> 'as'     # Not phonetically clear
'g' -> 'see'    # Not phonetically clear
'h' -> 'a'      # Not phonetically clear
'j' -> 'a'      # Not phonetically clear
'k' -> 'a'      # Not phonetically clear
'l' -> 'as'     # Not phonetically clear
'n' -> 'as'     # Not phonetically clear
'p' -> 'see'    # Not phonetically clear
'r' -> 'on'     # Not phonetically clear
's' -> 'as'     # Not phonetically clear
't' -> 'see'    # Not phonetically clear
'v' -> 'see'    # Not phonetically clear
'z' -> 'see'    # Not phonetically clear
'i' -> 'a'      # Sight word conflict (both are sight words)
'a' -> 'i'      # Sight word conflict (both are sight words)
```

**After:** 7 phonetically-sound mappings

**Kept (7 good mappings):**
```dart
'b' -> 'be'     // "b" sounds like "be"
'c' -> 'see'    // "c" sounds like "see"
'm' -> 'am'     // "m" often detected when saying "am"
'o' -> 'go'     // "oh" sounds like "go"
'q' -> 'you'    // "queue" sounds like "you"
'u' -> 'you'    // "u" sounds like "you"
'y' -> 'i'      // "why" sounds like "i"
```

### 2. Removed Partial Matching Logic

**Removed from `sherpa_recognizer.dart` (lines 707-725):**

```dart
// REMOVED - This caused false positives:
// Special handling for short expected words (2-3 letters) with single-letter tokens
// This handles cases like "N" when saying "in", "M" when saying "am", etc.
if (expectedWord.length <= 3 && expectedWord.length >= 2) {
  for (final token in normalizedTokens) {
    if (token.length == 1) {
      // Check if the single letter is the last letter of the expected word
      if (token.toLowerCase() == expectedWord.toLowerCase()[expectedWord.length - 1]) {
        return expectedWord;  // FALSE POSITIVE RISK!
      }
      // Also check if it's the first letter for very short words
      if (expectedWord.length == 2 && token.toLowerCase() == expectedWord.toLowerCase()[0]) {
        return expectedWord;  // FALSE POSITIVE RISK!
      }
    }
  }
}
```

**Replaced with:**
```dart
// Note: Partial matching logic removed as comprehensive homophone map now handles
// single-letter matches (e.g., 'm' -> 'am', 'c' -> 'see') through CMUdict-generated mappings
```

### 3. Updated Python Generator

**Modified `filter_relevant_homophones()` to:**
- Define a whitelist of phonetically sound single-letter mappings
- Filter out single letters not in the whitelist
- Prevent sight word conflicts (e.g., 'a' -> 'i' when both are sight words)

```python
# Single letters that are phonetically sound
good_single_letters = {
    'c': 'see',   # "c" sounds like "see"
    'b': 'be',    # "b" sounds like "be"
    'm': 'am',    # "m" sounds like "am" (partial)
    'u': 'you',   # "u" sounds like "you"
    'q': 'you',   # "queue" sounds like "you"
    'y': 'i',     # "why" sounds like "i"
    'o': 'go',    # "oh" sounds like "go"
}
```

## Results

### Before Cleanup
```
Total mappings: 3,534
Single-letter mappings: 24 (many causing false positives)
Partial matching logic: Present (causing false positives)
```

### After Cleanup
```
Total mappings: 3,517 (removed 17 problematic ones)
Single-letter mappings: 7 (all phonetically sound)
Partial matching logic: Removed
```

## Impact

### ✅ Benefits
1. **Fewer False Positives**: Removed 17 questionable single-letter mappings
2. **More Reliable**: Only keeps phonetically sound matches
3. **Cleaner Logic**: Removed complex partial matching code
4. **Still Comprehensive**: 3,517 mappings still cover vast majority of homophones

### ⚠️ Trade-offs
- Very slight reduction in coverage (17 edge cases removed)
- But those edge cases were causing MORE problems than they solved

## Testing Recommendations

Test words that were previously problematic:

### 1. Test "were" (main problem word)
```
Say "were" → Should match even if model hears "work", "wire", "worry"
```

### 2. Test short words without false positives
```
Say "in"  → Should match "in", NOT partial "n" from other words
Say "am"  → Should match "am", can accept "m" (phonetically sound)
Say "see" → Should match "see", can accept "c" (phonetically sound)
```

### 3. Test sight word conflicts are avoided
```
Say "a"  → Should match "a", NOT incorrectly map to "i"
Say "i"  → Should match "i", NOT incorrectly map to "a"
```

## Files Modified

1. ✅ `asset-generation/tools/generate_homophone_map.py`
   - Added single-letter whitelist
   - Added sight word conflict prevention
   
2. ✅ `lib/services/sight_word_homophones.dart` (regenerated)
   - Now contains 3,517 clean mappings
   - Only 7 phonetically-sound single-letter mappings
   
3. ✅ `lib/services/sherpa_recognizer.dart`
   - Removed partial matching logic (lines 707-725)
   - Replaced with comment explaining comprehensive map now handles this

## Summary

**We've significantly improved the homophone mapping system by:**
- Removing 17 questionable single-letter mappings that caused false positives
- Keeping only 7 phonetically-sound single-letter mappings
- Removing complex partial matching logic
- Maintaining comprehensive coverage (3,517 mappings)

**Result:** More reliable speech recognition with fewer false positives! 🎯

---

**Ready to test:** Hot reload and test "were" and other tricky words!

