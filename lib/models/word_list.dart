import 'dart:math';

/// Model representing the sight words list and game logic
class WordList {
  static final List<String> allWords = [
    // Week 1
    "you", "see",
    // Week 2
    "go", "i",
    // Week 3
    "has", "he",
    // Week 4
    "the", "had",
    // Week 5
    "and", "of",
    
    // Week 6
    "a", "we",
    // Week 7
    "is", "a",
    // Week 8
    "am", "at",
    // Week 9
    "to", "as",
    // Week 10
    "have", "in",
    
    // Week 11
    "it", "can",
    // Week 12
    "his", "him",
    // Week 13
    "on", "did",
    // Week 14
    "girl", "for",
    // Week 15
    "but", "up",
    
    // Week 16
    "all", "look",
    // Week 17
    "with", "her",
    // Week 18
    "what", "was",
    // Week 19
    "were", "said",
    // Week 20
    "that", "down",
    
    // Week 21
    "they", "boy",
    // Week 22
    "out", "do",
    // Week 23
    "little", "be",
    // Week 24
    "she", "there",
    // Week 25
    "then", "when",
    
    // Week 26
    "some", "red",
    // Week 27
    "orange", "yellow",
    // Week 28
    "green", "blue",
    // Week 29
    "purple", "black",
    // Week 30
    "gray", "pink",
    
    // Week 31
    "white", "brown",
  ];

  static const int maxWeeks = 31;
  static const int wordsPerWeek = 2;

  /// Generate a shuffled list of indices for words up to the given week number
  /// Each unique word appears exactly once, even if it appears multiple times in the word list
  /// weekNumber: The current week (1-31), includes all words from weeks 1 through weekNumber
  static List<int> generateShuffledIndicesForWeek(int weekNumber) {
    final random = Random();
    final int wordCount = weekNumber * wordsPerWeek;
    
    // First, collect unique words and their first occurrence index
    // This ensures each word appears only once, even if duplicated in the list
    final Map<String, int> wordToIndex = {};
    for (int i = 0; i < wordCount; i++) {
      final word = allWords[i];
      // Only add if we haven't seen this word before
      if (!wordToIndex.containsKey(word)) {
        wordToIndex[word] = i;
      }
    }
    
    // Get all unique indices (one per unique word)
    final List<int> uniqueIndices = wordToIndex.values.toList();
    
    // Fisher-Yates shuffle on the unique indices
    for (int i = 0; i < uniqueIndices.length; i++) {
      final int randomIndex = random.nextInt(uniqueIndices.length - i) + i;
      final int temp = uniqueIndices[i];
      uniqueIndices[i] = uniqueIndices[randomIndex];
      uniqueIndices[randomIndex] = temp;
    }
    
    return uniqueIndices;
  }

  /// Get the subset of words for a given week number (includes all weeks up to that week)
  static List<String> getWordsForWeek(int weekNumber) {
    final int wordCount = weekNumber * wordsPerWeek;
    return allWords.take(wordCount).toList();
  }

  /// Legacy method for backwards compatibility
  @Deprecated('Use generateShuffledIndicesForWeek instead')
  static List<int> generateShuffledIndices(int numWeeks) {
    return generateShuffledIndicesForWeek(numWeeks);
  }

  /// Legacy method for backwards compatibility
  @Deprecated('Use getWordsForWeek instead')
  static List<String> getWordsForWeeks(int numWeeks) {
    return getWordsForWeek(numWeeks);
  }

  /// Get a word by index
  static String getWord(int index) {
    if (index >= 0 && index < allWords.length) {
      return allWords[index];
    }
    return '';
  }

  /// Check if a phrase contains the expected word
  static bool phraseContainsWord(String phrase, String expectedWord) {
    final phraseLower = phrase.toLowerCase().trim();
    final expectedLower = expectedWord.toLowerCase().trim();
    
    if (phraseLower == expectedLower) {
      return true;
    }
    
    // Split the phrase into words and check each one
    final words = phraseLower.split(RegExp(r'\s+'));
    return words.contains(expectedLower);
  }
}


