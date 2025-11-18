import '../utils/app_logger.dart';

/// Service for intelligently grouping words into readable lines
/// 
/// Groups words into 3-5 word chunks with intelligent breaking at:
/// - End of sentences (. ! ?)
/// - Commas
/// - Conjunctions (and, but, or)
/// - Natural phrase boundaries
class WordGroupingService {
  /// Break points that suggest a good place to end a line
  static const Set<String> breakWords = {
    'and', 'but', 'or', 'so', 'yet', 'for', 'nor',
    'because', 'although', 'while', 'if', 'when', 'where',
  };
  
  static const _minWordsPerLine = 1;
  static const _targetWordsPerLine = 3;
  static const _maxWordsPerLine = 3;
  static const _maxCharactersPerLine = 18;
  
  /// Group words into short, natural phrases (≈3 words) with punctuation awareness.
  /// 
  /// Returns list of word groups, where each group is a list of word indices
  /// Example: [[0,1,2,3,4], [5,6,7], [8,9,10,11,12]]
  static List<List<int>> groupWords(
    List<String> words, {
    List<String>? displayWords,
  }) {
    if (words.isEmpty) return [];
    
    final groups = <List<int>>[];
    var currentGroup = <int>[];
    var currentCharCount = 0;
    
    for (int i = 0; i < words.length; i++) {
      final displayWord = displayWords != null && displayWords.length > i
          ? displayWords[i]
          : words[i];
      final normalizedLength = displayWord.replaceAll(RegExp(r'\s+'), '').length;
      
      currentGroup.add(i);
      currentCharCount += normalizedLength;
      if (currentGroup.length > 1) {
        currentCharCount++; // account for spaces between words
      }
      
      // Check if we should end this group
      final shouldBreak = _shouldBreakAfter(
        words,
        i,
        currentGroup.length,
        currentCharCount,
        displayWords: displayWords,
      );
      final bool overflowBreak = shouldBreak &&
          _isOverflow(currentGroup.length, currentCharCount);
      
      if (shouldBreak) {
        if (overflowBreak && currentGroup.length > 1) {
          final overflowWord = currentGroup.removeLast();
          currentCharCount -= _wordLength(words, overflowWord, displayWords);
          if (currentGroup.length >= 1 && currentCharCount > 0) {
            currentCharCount -= 1; // remove trailing space
          }
          groups.add(List.from(currentGroup));
          currentGroup = [overflowWord];
          currentCharCount = _wordLength(words, overflowWord, displayWords);
        } else {
          groups.add(List.from(currentGroup));
          currentGroup.clear();
          currentCharCount = 0;
        }
      }
    }
    
    // Add remaining words
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }
    
    AppLogger.speech.d(
      'Grouped ${words.length} words into ${groups.length} lines: '
      '${groups.map((g) => g.length).join(", ")}'
    );
    
    return groups;
  }
  
  /// Determine if we should break after this word
  static bool _shouldBreakAfter(
    List<String> words,
    int index,
    int groupSize,
    int groupCharCount, {
    List<String>? displayWords,
  }) {
    if (index >= words.length) return true;
    
    final rawWord = displayWords != null && displayWords.length > index
        ? displayWords[index]
        : words[index];
    final word = rawWord.toLowerCase();
    final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
    
    // Always break at max word or character length
    if (groupSize >= _maxWordsPerLine) return true;
    if (groupCharCount >= _maxCharactersPerLine && groupSize >= _minWordsPerLine) {
      return true;
    }
    
    final isSentenceEnd = _endsWithPunctuation(rawWord, {'.', '!', '?'});
    final isHardPause = _endsWithPunctuation(rawWord, {',', ';', ':'});
    
    // Allow short lines at sentence end even if < min
    if (isSentenceEnd && groupSize >= _minWordsPerLine) {
      return true;
    }
    
    if (groupSize < _minWordsPerLine) {
      return false;
    }
    
    // Prefer target length when punctuation or break words appear
    if (groupSize >= _targetWordsPerLine) {
      if (isSentenceEnd || isHardPause) return true;
      if (breakWords.contains(cleanWord)) return true;
      
      // Peek at next token for natural pause
      if (index + 1 < words.length) {
        final nextRaw = displayWords != null && displayWords.length > index + 1
            ? displayWords[index + 1]
            : words[index + 1];
        final nextClean = nextRaw.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
        final nextStartsNewSentence = _startsNewSentence(nextRaw);
        if (nextStartsNewSentence || breakWords.contains(nextClean)) {
          return true;
        }
      }
    }
    
    // Break on explicit newline markers
    if (rawWord.contains('\n')) return true;
    
    return false;
  }

  static bool _isOverflow(int groupSize, int charCount) {
    return groupSize >= _minWordsPerLine && charCount > _maxCharactersPerLine;
  }

  static int _wordLength(
    List<String> words,
    int index,
    List<String>? displayWords,
  ) {
    if (index < 0 || index >= words.length) return 0;
    final displayWord = displayWords != null && displayWords.length > index
        ? displayWords[index]
        : words[index];
    return displayWord.replaceAll(RegExp(r'\s+'), '').length;
  }
  
  /// Check if word ends with any of the given punctuation marks
  static bool _endsWithPunctuation(String word, Set<String> punctuation) {
    if (word.isEmpty) return false;
    return punctuation.any((p) => word.endsWith(p));
  }
  
  static bool _startsNewSentence(String word) {
    if (word.isEmpty) return false;
    final trimmed = word.trimLeft();
    if (trimmed.isEmpty) return false;
    final firstChar = trimmed[0];
    return firstChar == firstChar.toUpperCase() && _endsWithPunctuation(word, {'.', '!', '?', ':'});
  }
  
  /// Get the line index for a given word index
  static int getLineForWord(List<List<int>> groups, int wordIndex) {
    for (int i = 0; i < groups.length; i++) {
      if (groups[i].contains(wordIndex)) {
        return i;
      }
    }
    return groups.length - 1; // Default to last line
  }
  
  /// Get progress within a line (0.0 to 1.0)
  static double getLineProgress(List<int> lineWords, int currentWordIndex) {
    if (lineWords.isEmpty) return 0.0;
    if (!lineWords.contains(currentWordIndex)) return 0.0;
    
    final indexInLine = lineWords.indexOf(currentWordIndex);
    return indexInLine / lineWords.length;
  }
  
  /// Get smooth interpolated progress accounting for timing
  /// 
  /// Uses reading rate estimation to provide smooth progress between
  /// word declarations, reducing perceived "jumpiness"
  static double getSmoothProgress({
    required List<int> lineWords,
    required int lastConfirmedWord,
    required double timeSinceLastWord,
    required double estimatedWordsPerSecond,
  }) {
    if (lineWords.isEmpty) return 0.0;
    
    // Find position of last confirmed word in line
    int confirmedIndex = -1;
    for (int i = 0; i < lineWords.length; i++) {
      if (lineWords[i] == lastConfirmedWord) {
        confirmedIndex = i;
        break;
      }
    }
    
    if (confirmedIndex < 0) {
      // Word not in this line - check if before or after
      if (lastConfirmedWord < lineWords.first) return 0.0;
      if (lastConfirmedWord > lineWords.last) return 1.0;
      return 0.0;
    }
    
    // Estimate how many more words completed based on time
    final estimatedWordsAdvanced = timeSinceLastWord * estimatedWordsPerSecond;
    final smoothIndex = confirmedIndex + estimatedWordsAdvanced;
    
    // Convert to progress (0.0 to 1.0)
    final progress = smoothIndex / lineWords.length;
    
    // Clamp to [0, 1]
    return progress.clamp(0.0, 1.0);
  }
}

