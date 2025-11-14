/// Service for generating and managing stories via GenAI API
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/story_models.dart';
import '../models/learning_progress.dart';
import '../models/child_profile.dart';
import '../utils/app_logger.dart';
import 'profile_service.dart';

class StoryService {
  // API base URL - use localhost for development
  // In production, this would be a deployed service URL
  static const String _baseUrl = 'http://localhost:8001';
  
  final http.Client _client;
  final ProfileService _profileService;
  
  StoryService({
    http.Client? client,
    ProfileService? profileService,
  }) : _client = client ?? http.Client(),
       _profileService = profileService ?? ProfileService();
  
  /// Generate a story chapter for the current profile
  Future<StoryChapter> generateStory({
    required String profileId,
    String? epicArcId,
    int? chapterNum,
  }) async {
    try {
      AppLogger.system.d('Generating story for profile: $profileId');
      
      // Load profile info
      final profile = await _profileService.loadProfileById(profileId);
      if (profile == null) {
        throw Exception('Profile not found: $profileId');
      }
      
      // Load learning progress
      final progress = await _profileService.loadProgress(profileId) ??
          LearningProgress(
            firstSessionDate: DateTime.now(),
            lastSessionDate: DateTime.now(),
          );
      
      // Select target words based on mastery
      final targetWords = _selectTargetWords(progress);
      
      AppLogger.system.d('Selected ${targetWords.length} target words');
      
      // Build request
      final requestBody = {
        'child_name': profile.name,
        'age': profile.ageYears ?? 5,
        'theme': 'adventure',  // TODO: Get from profile preferences
        'target_words': targetWords.map((w) => {
          'word': w['word'],
          'mastery_level': w['mastery_level'],
        }).toList(),
        'chapter_num': chapterNum ?? 1,
        'total_chapters': 10,
        'num_choices': 2,
      };
      
      // Call API
      final response = await _client.post(
        Uri.parse('$_baseUrl/generate-story'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final story = StoryChapter.fromJson(json);
        
        AppLogger.system.emoji('✅', 'Story generated: ${story.title}');
        return story;
      } else {
        throw Exception('Story generation failed: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      AppLogger.system.e('Error generating story', error: e);
      rethrow;
    }
  }
  
  /// Generate an epic arc for the profile
  Future<EpicArc> generateEpicArc({
    required String profileId,
    String? theme,
  }) async {
    try {
      AppLogger.system.d('Generating epic arc for profile: $profileId');
      
      final profile = await _profileService.loadProfileById(profileId);
      if (profile == null) {
        throw Exception('Profile not found: $profileId');
      }
      
      final requestBody = {
        'child_name': profile.name,
        'age': profile.ageYears ?? 5,
        'theme': theme ?? 'adventure',
        'total_weeks': 25,
        'total_words': 100,
      };
      
      final response = await _client.post(
        Uri.parse('$_baseUrl/generate-epic'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final epic = EpicArc.fromJson(json);
        
        AppLogger.system.emoji('✅', 'Epic arc generated: ${epic.title}');
        return epic;
      } else {
        throw Exception('Epic generation failed: ${response.statusCode}');
      }
      
    } catch (e) {
      AppLogger.system.e('Error generating epic arc', error: e);
      rethrow;
    }
  }
  
  /// Calculate word spacing for a story
  Future<Map<String, List<int>>> calculateWordSpacing({
    required List<Map<String, dynamic>> words,
    int numBeats = 12,
  }) async {
    try {
      final requestBody = {
        'words': words,
        'num_beats': numBeats,
        'strategy': 'adaptive',
      };
      
      final response = await _client.post(
        Uri.parse('$_baseUrl/calculate-spacing'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final spacing = json['spacing'] as Map<String, dynamic>;
        
        // Convert to Map<String, List<int>>
        return spacing.map((word, positions) {
          return MapEntry(
            word,
            (positions as List<dynamic>).map((p) => p as int).toList(),
          );
        });
      } else {
        throw Exception('Spacing calculation failed: ${response.statusCode}');
      }
      
    } catch (e) {
      AppLogger.system.e('Error calculating word spacing', error: e);
      rethrow;
    }
  }
  
  /// Get available story themes
  Future<List<Map<String, String>>> getThemes() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/themes'),
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final themes = json['themes'] as List<dynamic>;
        
        return themes.map((t) {
          final theme = t as Map<String, dynamic>;
          return {
            'id': theme['id'] as String,
            'name': theme['name'] as String,
            'description': theme['description'] as String,
          };
        }).toList();
      } else {
        throw Exception('Failed to load themes: ${response.statusCode}');
      }
      
    } catch (e) {
      AppLogger.system.e('Error loading themes', error: e);
      rethrow;
    }
  }
  
  /// Select target words based on mastery levels
  /// Returns 60% easy words, 40% challenging words
  List<Map<String, dynamic>> _selectTargetWords(LearningProgress progress) {
    final allWords = progress.wordProgress.values.toList();
    
    // Separate by mastery level
    final easy = allWords.where((w) => w.successRate >= 0.7).toList();
    final challenging = allWords.where((w) => w.successRate < 0.7).toList();
    
    // Select 3 easy, 2 challenging
    final selectedEasy = (easy..shuffle()).take(3).toList();
    final selectedChallenging = (challenging..shuffle()).take(2).toList();
    
    final selected = [...selectedEasy, ...selectedChallenging];
    
    return selected.map((w) => {
      'word': w.word,
      'mastery_level': w.successRate,
    }).toList();
  }
  
  /// Check if GenAI service is available
  Future<bool> isServiceAvailable() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 2));
      
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.system.w('GenAI service not available: $e');
      return false;
    }
  }
  
  void dispose() {
    _client.close();
  }
}

/// Extension on ProfileService to load by ID
extension ProfileServiceExtension on ProfileService {
  Future<ChildProfile?> loadProfileById(String profileId) async {
    final profiles = await loadProfiles();
    return profiles.where((p) => p.id == profileId).firstOrNull;
  }
}

