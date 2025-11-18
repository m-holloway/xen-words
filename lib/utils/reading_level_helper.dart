import 'dart:math';

import '../models/word_list.dart';

class ReadingBand {
  final int level;
  final String label;
  final String description;
  final String gradeBand;
  final String lexileBand;
  final List<String> hallmarks;
  final String libraryReference;

  const ReadingBand({
    required this.level,
    required this.label,
    required this.description,
    required this.gradeBand,
    required this.lexileBand,
    required this.hallmarks,
    required this.libraryReference,
  });

  Map<String, dynamic> toJson() {
    return {
      'level': level,
      'label': label,
      'description': description,
      'grade_band': gradeBand,
      'lexile_band': lexileBand,
      'hallmarks': hallmarks,
      'library_reference': libraryReference,
    };
  }

  factory ReadingBand.fromJson(Map<String, dynamic> json) {
    return ReadingBand(
      level: (json['level'] as num?)?.toInt() ?? 1,
      label: json['label']?.toString() ?? 'Level 1 • Emerging Reader',
      description: json['description']?.toString() ?? '',
      gradeBand: json['grade_band']?.toString() ?? '',
      lexileBand: json['lexile_band']?.toString() ?? '',
      hallmarks: (json['hallmarks'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      libraryReference: json['library_reference']?.toString() ?? '',
    );
  }
}

/// Utility helpers for mapping UI reading levels to familiar vocab + descriptors.
class ReadingLevelHelper {
  /// Maximum supported reading level value in the UI.
  static const int maxLevel = 5;

  /// Minimum supported reading level value in the UI.
  static const int minLevel = 1;

  static final List<ReadingBand> _bands = [
    const ReadingBand(
      level: 1,
      label: 'Level 1 • Emerging Reader',
      description:
          'Decodable text with heavy picture support and repeated sight-word patterns. Inspired by ALA/Step-Into-Reading Level 1.',
      gradeBand: 'Late Pre-K to Kindergarten',
      lexileBand: 'BR to 150L',
      hallmarks: [
        '1 short sentence per page',
        'Repetition of first ~50 high-frequency words',
        'Large font, strong picture cues',
      ],
      libraryReference: 'ALA Early Reader Level 1 / Penguin Young Readers Level 1',
    ),
    const ReadingBand(
      level: 2,
      label: 'Level 2 • Developing Reader',
      description:
          'Supports children transitioning beyond pure sight words. Matches library “Level 2: Reading with Help” titles.',
      gradeBand: 'Kindergarten to Early Grade 1',
      lexileBand: '150L – 300L',
      hallmarks: [
        '2–4 sentences per page',
        'Simple story arc with dialogue tags',
        'Introduces consonant blends & two-syllable words',
      ],
      libraryReference: 'Step-Into-Reading Level 2 / I Can Read! Level 2',
    ),
    const ReadingBand(
      level: 3,
      label: 'Level 3 • Transitional Reader',
      description:
          'Paragraphs, early chapters, and topic sentences appear—aligned with library Level 3 books.',
      gradeBand: 'Grades 1–2',
      lexileBand: '300L – 500L',
      hallmarks: [
        'Paragraphs of 3–5 sentences',
        'Richer dialogue and descriptive language',
        'Mixture of familiar and tier-two vocabulary',
      ],
      libraryReference: 'ALA Level 3 / Penguin Young Readers Level 3',
    ),
    const ReadingBand(
      level: 4,
      label: 'Level 4 • Fluent Reader',
      description:
          'Full chapters, multiple scenes, and more precise vocabulary mirroring library Level 4 collections.',
      gradeBand: 'Grades 2–3',
      lexileBand: '500L – 650L',
      hallmarks: [
        'Complex sentences with clauses',
        'Content-specific vocabulary explained in context',
        'Themes of problem solving and growth mindset',
      ],
      libraryReference: 'ALA Level 4 / I Can Read! Level 4',
    ),
    const ReadingBand(
      level: 5,
      label: 'Level 5 • Confident Reader',
      description:
          'Comparable to “Ready for Chapters” paperbacks; multi-paragraph scenes and higher-concept themes.',
      gradeBand: 'Grades 3–4',
      lexileBand: '650L – 750L',
      hallmarks: [
        'Multiple paragraphs per page',
        'Figurative language & richer world building',
        'Encourages inferencing and character motivation',
      ],
      libraryReference: 'ALA Level 5 / Ready-to-Read Level 4',
    ),
  ];

  /// Returns a sanitized level within the supported range.
  static int normalizeLevel(int level) {
    return max(minLevel, min(level, maxLevel));
  }

  static List<ReadingBand> get allBands => List.unmodifiable(_bands);

  static ReadingBand bandForLevel(int level) {
    final normalized = normalizeLevel(level);
    return _bands.firstWhere(
      (band) => band.level == normalized,
      orElse: () => _bands.first,
    );
  }

  static List<String> vocabularyForBand(ReadingBand band, {int wordsPerBand = 30}) {
    final startIndex = (band.level - 1) * wordsPerBand;
    final safeStart = startIndex.clamp(0, WordList.allWords.length);
    final endIndex = min(safeStart + wordsPerBand, WordList.allWords.length);
    if (safeStart >= endIndex) {
      return WordList.allWords.take(wordsPerBand).toList();
    }
    final slice = WordList.allWords.sublist(safeStart, endIndex);
    if (slice.isNotEmpty) {
      return slice;
    }
    return WordList.allWords.take(wordsPerBand).toList();
  }
}

