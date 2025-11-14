import 'package:flutter/material.dart';

/// Child profile for multi-user support
class ChildProfile {
  final String id; // UUID for unique identification
  final String name; // Child's first name
  final int? ageYears; // Optional age in years
  final DateTime createdDate;
  final DateTime lastActiveDate;
  final Color color; // Theme color for profile
  final String emoji; // Fun emoji identifier
  
  // Settings per profile
  final int currentWeek;
  final String rugFontFamily;
  
  const ChildProfile({
    required this.id,
    required this.name,
    this.ageYears,
    required this.createdDate,
    required this.lastActiveDate,
    this.color = Colors.blue,
    this.emoji = '🎓',
    this.currentWeek = 1,
    this.rugFontFamily = 'Quicksand',
  });
  
  /// Create from JSON
  factory ChildProfile.fromJson(Map<String, dynamic> json) {
    return ChildProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      ageYears: json['ageYears'] as int?,
      createdDate: DateTime.parse(json['createdDate'] as String),
      lastActiveDate: DateTime.parse(json['lastActiveDate'] as String),
      color: Color(json['color'] as int? ?? Colors.blue.value),
      emoji: json['emoji'] as String? ?? '🎓',
      currentWeek: json['currentWeek'] as int? ?? 1,
      rugFontFamily: json['rugFontFamily'] as String? ?? 'Quicksand',
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ageYears': ageYears,
      'createdDate': createdDate.toIso8601String(),
      'lastActiveDate': lastActiveDate.toIso8601String(),
      'color': color.value,
      'emoji': emoji,
      'currentWeek': currentWeek,
      'rugFontFamily': rugFontFamily,
    };
  }
  
  /// Copy with updated values
  ChildProfile copyWith({
    String? id,
    String? name,
    int? ageYears,
    DateTime? createdDate,
    DateTime? lastActiveDate,
    Color? color,
    String? emoji,
    int? currentWeek,
    String? rugFontFamily,
  }) {
    return ChildProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      ageYears: ageYears ?? this.ageYears,
      createdDate: createdDate ?? this.createdDate,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
      color: color ?? this.color,
      emoji: emoji ?? this.emoji,
      currentWeek: currentWeek ?? this.currentWeek,
      rugFontFamily: rugFontFamily ?? this.rugFontFamily,
    );
  }
  
  /// Create a guest profile (not saved)
  factory ChildProfile.guest() {
    final now = DateTime.now();
    return ChildProfile(
      id: 'guest',
      name: 'Guest',
      createdDate: now,
      lastActiveDate: now,
      color: Colors.grey,
      emoji: '👤',
    );
  }
  
  /// Check if this is the guest profile
  bool get isGuest => id == 'guest';
  
  /// Get display name with emoji
  String get displayName => '$emoji $name';
  
  /// Get age display
  String? get ageDisplay => ageYears != null ? '$ageYears years old' : null;
  
  /// Get activity display
  String get lastActiveDisplay {
    final now = DateTime.now();
    final difference = now.difference(lastActiveDate);
    
    if (difference.inDays == 0) {
      return 'Active today';
    } else if (difference.inDays == 1) {
      return 'Active yesterday';
    } else if (difference.inDays < 7) {
      return 'Active ${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return 'Active $weeks week${weeks > 1 ? 's' : ''} ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return 'Active $months month${months > 1 ? 's' : ''} ago';
    }
  }
}

/// Available profile colors
class ProfileColors {
  static const List<Color> available = [
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.red,
    Colors.indigo,
    Colors.amber,
    Colors.cyan,
  ];
  
  static Color random() {
    return available[DateTime.now().millisecond % available.length];
  }
}

/// Available profile emojis
class ProfileEmojis {
  static const List<String> available = [
    '🎓', '🌟', '🚀', '🎨', '⚡', '🌈', '🎯', '🎪',
    '🦄', '🐶', '🐱', '🐼', '🦊', '🐸', '🦋', '🐝',
    '🌸', '🌺', '🌻', '🍀', '🍎', '🍓', '🍕', '🎮',
  ];
  
  static String random() {
    return available[DateTime.now().millisecond % available.length];
  }
}

