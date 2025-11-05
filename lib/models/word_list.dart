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

  /// Generate a shuffled list of indices for the given number of weeks
  static List<int> generateShuffledIndices(int numWeeks) {
    final random = Random();
    final int wordCount = numWeeks * wordsPerWeek;
    
    // Create a list of indices from 0 to wordCount-1
    final List<int> indices = List.generate(wordCount, (index) => index);
    
    // Fisher-Yates shuffle
    for (int i = 0; i < wordCount; i++) {
      final int randomIndex = random.nextInt(wordCount - i) + i;
      final int temp = indices[i];
      indices[i] = indices[randomIndex];
      indices[randomIndex] = temp;
    }
    
    return indices;
  }

  /// Get the subset of words for a given number of weeks
  static List<String> getWordsForWeeks(int numWeeks) {
    final int wordCount = numWeeks * wordsPerWeek;
    return allWords.take(wordCount).toList();
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


