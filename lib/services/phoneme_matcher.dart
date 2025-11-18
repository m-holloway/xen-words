import 'dart:math' as math;

/// Phoneme-based fuzzy word matching for speech alignment
/// 
/// Based on Python validation with CMU phoneme dictionary
class PhonemeMatcher {
  // Simplified CMU dictionary for common sight words
  static const Map<String, List<String>> _cmuDict = {
    // Common sight words
    'you': ['Y', 'UW'],
    'are': ['AA', 'R'],
    'see': ['S', 'IY'],
    'the': ['DH', 'AH'],
    'and': ['AE', 'N', 'D'],
    'your': ['Y', 'UH', 'R'],
    'in': ['IH', 'N'],
    'on': ['AA', 'N'],
    'to': ['T', 'UW'],
    'go': ['G', 'OW'],
    'has': ['HH', 'AE', 'Z'],
    'had': ['HH', 'AE', 'D'],
    'he': ['HH', 'IY'],
    'she': ['SH', 'IY'],
    'we': ['W', 'IY'],
    'is': ['IH', 'Z'],
    'am': ['AE', 'M'],
    'at': ['AE', 'T'],
    'as': ['AE', 'Z'],
    'have': ['HH', 'AE', 'V'],
    'it': ['IH', 'T'],
    'can': ['K', 'AE', 'N'],
    'his': ['HH', 'IH', 'Z'],
    'him': ['HH', 'IH', 'M'],
    'did': ['D', 'IH', 'D'],
    'for': ['F', 'AO', 'R'],
    'but': ['B', 'AH', 'T'],
    'up': ['AH', 'P'],
    'all': ['AO', 'L'],
    'look': ['L', 'UH', 'K'],
    'with': ['W', 'IH', 'TH'],
    'her': ['HH', 'ER'],
    'what': ['W', 'AH', 'T'],
    'was': ['W', 'AH', 'Z'],
    'were': ['W', 'ER'],
    'said': ['S', 'EH', 'D'],
    'that': ['DH', 'AE', 'T'],
    'down': ['D', 'AW', 'N'],
    'they': ['DH', 'EY'],
    'out': ['AW', 'T'],
    'do': ['D', 'UW'],
    'be': ['B', 'IY'],
    'there': ['DH', 'EH', 'R'],
    'then': ['DH', 'EH', 'N'],
    'when': ['W', 'EH', 'N'],
    'some': ['S', 'AH', 'M'],
    'today': ['T', 'AH', 'D', 'EY'],
    'put': ['P', 'UH', 'T'],
    'step': ['S', 'T', 'EH', 'P'],
    'like': ['L', 'AY', 'K'],
    'heart': ['HH', 'AA', 'R', 'T'],
    'jumps': ['JH', 'AH', 'M', 'P', 'S'],
    'could': ['K', 'UH', 'D'],
    'lead': ['L', 'IY', 'D'],
    
    // Colors
    'red': ['R', 'EH', 'D'],
    'blue': ['B', 'L', 'UW'],
    'green': ['G', 'R', 'IY', 'N'],
    'yellow': ['Y', 'EH', 'L', 'OW'],
    'orange': ['AO', 'R', 'IH', 'N', 'JH'],
    'purple': ['P', 'ER', 'P', 'AH', 'L'],
    'black': ['B', 'L', 'AE', 'K'],
    'white': ['W', 'AY', 'T'],
    'pink': ['P', 'IH', 'NG', 'K'],
    'brown': ['B', 'R', 'AW', 'N'],
    'gray': ['G', 'R', 'EY'],
  };
  
  // Vowel phonemes for syllable counting
  static const Set<String> _vowels = {
    'AA', 'AE', 'AH', 'AO', 'AW', 'AY',
    'EH', 'ER', 'EY', 'IH', 'IY', 'OW',
    'OY', 'UH', 'UW'
  };
  
  /// Convert word to phonemes
  static List<String> wordToPhonemes(String word) {
    final normalized = word.toLowerCase().trim();
    
    // Check dictionary first
    if (_cmuDict.containsKey(normalized)) {
      return _cmuDict[normalized]!;
    }
    
    // Fall back to simple guess
    return _guessPhonemes(normalized);
  }
  
  /// Guess phonemes from spelling (simple heuristics)
  static List<String> _guessPhonemes(String word) {
    if (word.isEmpty) return [];
    
    final phonemes = <String>[];
    int i = 0;
    
    while (i < word.length) {
      // Check digraphs
      if (i + 1 < word.length) {
        final digraph = word.substring(i, i + 2);
        
        switch (digraph) {
          case 'sh':
            phonemes.add('SH');
            i += 2;
            continue;
          case 'ch':
            phonemes.add('CH');
            i += 2;
            continue;
          case 'th':
            phonemes.add('TH');
            i += 2;
            continue;
          case 'ee':
          case 'ea':
            phonemes.add('IY');
            i += 2;
            continue;
          case 'oo':
            phonemes.add('UW');
            i += 2;
            continue;
          case 'ay':
          case 'ai':
            phonemes.add('EY');
            i += 2;
            continue;
          case 'ow':
            phonemes.add('AW');
            i += 2;
            continue;
        }
      }
      
      // Single letters
      final char = word[i];
      switch (char) {
        // Vowels
        case 'a':
          phonemes.add('AE');
          break;
        case 'e':
          phonemes.add('EH');
          break;
        case 'i':
          phonemes.add('IH');
          break;
        case 'o':
          phonemes.add('AA');
          break;
        case 'u':
          phonemes.add('AH');
          break;
        
        // Consonants
        case 'y':
          phonemes.add('Y');
          break;
        case 'n':
          phonemes.add('N');
          break;
        case 'd':
          phonemes.add('D');
          break;
        case 'l':
          phonemes.add('L');
          break;
        case 't':
          phonemes.add('T');
          break;
        case 'r':
          phonemes.add('R');
          break;
        case 's':
          phonemes.add('S');
          break;
        case 'w':
          phonemes.add('W');
          break;
        case 'g':
          phonemes.add('G');
          break;
        case 'b':
          phonemes.add('B');
          break;
        case 'p':
          phonemes.add('P');
          break;
        case 'm':
          phonemes.add('M');
          break;
        case 'f':
          phonemes.add('F');
          break;
        case 'v':
          phonemes.add('V');
          break;
        case 'k':
        case 'c':
          phonemes.add('K');
          break;
        case 'h':
          phonemes.add('HH');
          break;
        case 'z':
          phonemes.add('Z');
          break;
        case 'j':
          phonemes.add('JH');
          break;
      }
      
      i++;
    }
    
    return phonemes.isNotEmpty ? phonemes : [word.toUpperCase()];
  }
  
  /// Count syllables (vowel phonemes)
  static int countSyllables(List<String> phonemes) {
    return phonemes.where((p) => _vowels.contains(p)).length;
  }
  
  /// Calculate phonetic similarity between two phoneme sequences
  /// 
  /// Returns score 0.0-1.0:
  /// - 1.0 = perfect match
  /// - 0.7-0.9 = good match (likely same word)
  /// - 0.5-0.7 = possible match
  /// - <0.5 = poor match
  static double phoneticSimilarity(List<String> phonemes1, List<String> phonemes2) {
    if (phonemes1.isEmpty || phonemes2.isEmpty) return 0.0;
    
    double score = 0.0;
    
    // 1. Syllable count match (strong signal)
    final syl1 = countSyllables(phonemes1);
    final syl2 = countSyllables(phonemes2);
    if (syl1 == syl2 && syl1 > 0) {
      score += 0.4;
    }
    
    // 2. First phoneme match (important for word identity)
    if (phonemes1.first == phonemes2.first) {
      score += 0.2;
    }
    
    // 3. Common phonemes (overlap)
    final set1 = phonemes1.toSet();
    final set2 = phonemes2.toSet();
    if (set1.isNotEmpty || set2.isNotEmpty) {
      final overlap = set1.intersection(set2).length;
      final maxLen = math.max(set1.length, set2.length);
      score += (overlap / maxLen) * 0.3;
    }
    
    // 4. Sequence order bonus (simple edit distance approximation)
    if (phonemes1.length > 1 && phonemes2.length > 1) {
      int matches = 0;
      final minLen = math.min(phonemes1.length, phonemes2.length);
      
      for (int i = 0; i < minLen; i++) {
        if (phonemes1[i] == phonemes2[i]) {
          matches++;
        }
      }
      
      score += (matches / minLen) * 0.1;
    }
    
    return math.min(1.0, score);
  }
  
  /// Calculate similarity between two words
  static double wordSimilarity(String word1, String word2) {
    if (word1 == word2) return 1.0;
    
    final phonemes1 = wordToPhonemes(word1);
    final phonemes2 = wordToPhonemes(word2);
    
    return phoneticSimilarity(phonemes1, phonemes2);
  }
  
  /// Find best match for a word in a list of candidates
  /// 
  /// Returns (index, score) of best match
  static (int, double) findBestMatch(String targetWord, List<String> candidates, {int startIndex = 0}) {
    if (candidates.isEmpty) return (-1, 0.0);
    
    final targetPhonemes = wordToPhonemes(targetWord);
    int bestIndex = startIndex;
    double bestScore = 0.0;
    
    for (int i = startIndex; i < candidates.length; i++) {
      final candidatePhonemes = wordToPhonemes(candidates[i]);
      final score = phoneticSimilarity(targetPhonemes, candidatePhonemes);
      
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    
    return (bestIndex, bestScore);
  }
  
  /// Calculate similarity between two individual phonemes
  /// 
  /// Handles voiced/voiceless pairs and vowel similarity
  static double phonemeSimilarity(String p1, String p2) {
    if (p1 == p2) return 1.0;
    
    // Voiced/voiceless pairs
    const voicedPairs = [
      ['P', 'B'], ['T', 'D'], ['K', 'G'],
      ['F', 'V'], ['S', 'Z'], ['TH', 'DH'],
    ];
    
    for (final pair in voicedPairs) {
      if ((p1 == pair[0] && p2 == pair[1]) || 
          (p1 == pair[1] && p2 == pair[0])) {
        return 0.9;
      }
    }
    
    // Similar vowels
    if (_vowels.contains(p1) && _vowels.contains(p2)) {
      return 0.75;
    }
    
    return 0.3;  // Different sounds
  }
  
  /// Convert text to phoneme sequence with word boundaries
  /// 
  /// Returns (phonemes, word_boundaries, words)
  static (List<String>, List<int>, List<String>) textToPhonemes(String text) {
    final words = text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    
    final phonemes = <String>[];
    final boundaries = <int>[0];
    
    for (final word in words) {
      final wordPhonemes = wordToPhonemes(word);
      phonemes.addAll(wordPhonemes);
      boundaries.add(phonemes.length);
    }
    
    // Remove last boundary (it's the total length)
    if (boundaries.isNotEmpty) {
      boundaries.removeLast();
    }
    
    return (phonemes, boundaries, words);
  }
  
  /// Score alignment of detected phonemes to script phonemes
  /// 
  /// This is the KEY ALGORITHM from Python V7!
  /// Returns (score, last_matched_script_index)
  static (double, int) scorePhonemeSequenceAlignment(
    List<String> detectedPhonemes,
    List<String> scriptPhonemes,
    int startIndex,
  ) {
    if (detectedPhonemes.isEmpty || scriptPhonemes.isEmpty) {
      return (0.0, startIndex);
    }
    
    double totalScore = 0.0;
    int detectedIdx = 0;
    int scriptIdx = startIndex;
    int lastMatchedIdx = startIndex;
    
    // Walk through detected phonemes, trying to match to script
    while (detectedIdx < detectedPhonemes.length && scriptIdx < scriptPhonemes.length) {
      final similarity = phonemeSimilarity(
        detectedPhonemes[detectedIdx],
        scriptPhonemes[scriptIdx],
      );
      
      if (similarity > 0.7) {
        // Good match - advance both
        totalScore += similarity;
        lastMatchedIdx = scriptIdx;
        detectedIdx++;
        scriptIdx++;
      } else if (similarity > 0.5) {
        // Weak match - count it but reduce score
        totalScore += similarity * 0.8;
        lastMatchedIdx = scriptIdx;
        detectedIdx++;
        scriptIdx++;
      } else {
        // No match - skip detected phoneme (recognition error)
        detectedIdx++;
      }
    }
    
    // Normalize by detected length
    final avgScore = totalScore / detectedPhonemes.length;
    
    return (avgScore, lastMatchedIdx);
  }
  
  /// Map phoneme index to word index
  static int phonemeToWordIndex(int phonemeIdx, List<int> wordBoundaries) {
    if (wordBoundaries.isEmpty) return 0;
    
    phonemeIdx = math.max(0, phonemeIdx);
    
    for (int i = wordBoundaries.length - 1; i >= 0; i--) {
      if (phonemeIdx >= wordBoundaries[i]) {
        return i;
      }
    }
    
    return 0;
  }
}

