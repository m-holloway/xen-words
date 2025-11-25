import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/learning_progress.dart';
import '../utils/app_logger.dart';

/// Service for managing app preferences
class PreferencesService {
  static const String _keyCurrentWeek = 'current_week';
  static const String _keyAutoAdvanceEnabled = 'auto_advance_enabled';
  static const String _keyAdvanceDayOfWeek = 'advance_day_of_week';
  static const String _keyWordsPerWeek = 'words_per_week';
  static const String _keyLastAdvanceDate = 'last_advance_date';
  static const String _keyChildName = 'child_name';
  static const String _keyRugFontFamily = 'rug_font_family';
  static const String _keyLearningProgress = 'learning_progress';
  static const String _keyOnboardingComplete = 'onboarding_complete';
  static const String _keyStoryPersonalization = 'story_personalization_notes';
  static const String _keyStoryUseChildName = 'story_use_child_name';
  static const String _keyStoryGeneratorDraft = 'story_generator_draft_v1';
  static const String _keyStoryModelId = 'story_model_id';
  static const String _keyCoverImageModelId = 'cover_image_model_id';
  static const String _keyPanelImageModelId = 'panel_image_model_id';

  /// Load settings from preferences
  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final currentWeek = prefs.getInt(_keyCurrentWeek) ?? 1;
    final autoAdvanceEnabled = prefs.getBool(_keyAutoAdvanceEnabled) ?? true;
    final advanceDayOfWeek = prefs.getInt(_keyAdvanceDayOfWeek) ?? 0; // Sunday
    final wordsPerWeek = prefs.getInt(_keyWordsPerWeek) ?? 2;
    final childName = prefs.getString(_keyChildName) ?? '';
    final rugFontFamily = prefs.getString(_keyRugFontFamily) ?? 'Quicksand';
    
    DateTime? lastAdvanceDate;
    final lastAdvanceTimestamp = prefs.getInt(_keyLastAdvanceDate);
    if (lastAdvanceTimestamp != null) {
      lastAdvanceDate = DateTime.fromMillisecondsSinceEpoch(lastAdvanceTimestamp);
    }
    
    print('⚙️ Loading settings: childName="$childName", font="$rugFontFamily", currentWeek=$currentWeek');
    
    var settings = AppSettings(
      currentWeek: currentWeek,
      autoAdvanceEnabled: autoAdvanceEnabled,
      advanceDayOfWeek: advanceDayOfWeek,
      wordsPerWeek: wordsPerWeek,
      lastAdvanceDate: lastAdvanceDate,
      childName: childName,
      rugFontFamily: rugFontFamily,
    );
    
    // Check if we should auto-advance
    if (settings.shouldAdvanceWeek()) {
      settings = settings.copyWith(
        currentWeek: (settings.currentWeek + 1).clamp(1, 31),
        lastAdvanceDate: DateTime.now(),
      );
      // Save the updated week
      await saveSettings(settings);
    }
    
    return settings;
  }

  /// Save settings to preferences
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setInt(_keyCurrentWeek, settings.currentWeek);
    await prefs.setBool(_keyAutoAdvanceEnabled, settings.autoAdvanceEnabled);
    await prefs.setInt(_keyAdvanceDayOfWeek, settings.advanceDayOfWeek);
    await prefs.setInt(_keyWordsPerWeek, settings.wordsPerWeek);
    await prefs.setString(_keyChildName, settings.childName);
    await prefs.setString(_keyRugFontFamily, settings.rugFontFamily);
    
    if (settings.lastAdvanceDate != null) {
      await prefs.setInt(
        _keyLastAdvanceDate,
        settings.lastAdvanceDate!.millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_keyLastAdvanceDate);
    }
    
    print('💾 Saved settings: childName="${settings.childName}", font="${settings.rugFontFamily}", currentWeek=${settings.currentWeek}');
  }

  /// Update current week
  Future<void> updateCurrentWeek(int week) async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(currentWeek: week));
  }

  /// Update auto-advance settings
  Future<void> updateAutoAdvance(bool enabled, int dayOfWeek) async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(
      autoAdvanceEnabled: enabled,
      advanceDayOfWeek: dayOfWeek,
    ));
  }
  
  /// Load learning progress
  Future<LearningProgress?> loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final progressJson = prefs.getString(_keyLearningProgress);
      
      if (progressJson == null) {
        return null;
      }
      
      final data = jsonDecode(progressJson) as Map<String, dynamic>;
      return LearningProgress.fromJson(data);
    } catch (e) {
      AppLogger.storage.e('Error loading progress', error: e);
      return null;
    }
  }
  
  /// Save learning progress
  Future<void> saveProgress(LearningProgress progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final progressJson = jsonEncode(progress.toJson());
      await prefs.setString(_keyLearningProgress, progressJson);
      AppLogger.storage.d('Saved learning progress');
    } catch (e) {
      AppLogger.storage.e('Error saving progress', error: e);
      rethrow;
    }
  }
  
  /// Check if onboarding is complete
  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingComplete) ?? false;
  }
  
  /// Set onboarding complete status
  Future<void> setOnboardingComplete(bool complete) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingComplete, complete);
    AppLogger.ui.i('Onboarding complete set to: $complete');
  }
  
  /// Clear all app data (for "Delete All Data" feature)
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    AppLogger.storage.i('All app data cleared');
  }

  Future<String> getStoryPersonalizationNotes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoryPersonalization) ?? '';
  }

  Future<void> setStoryPersonalizationNotes(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(_keyStoryPersonalization);
    } else {
      await prefs.setString(_keyStoryPersonalization, value);
    }
  }

  Future<bool> getStoryUseChildName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyStoryUseChildName) ?? false;
  }

  Future<void> setStoryUseChildName(bool useChildName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStoryUseChildName, useChildName);
  }

  Future<String?> getStoryModelId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoryModelId);
  }

  Future<void> setStoryModelId(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStoryModelId, modelId);
  }

  Future<String?> getCoverImageModelId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCoverImageModelId);
  }

  Future<void> setCoverImageModelId(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCoverImageModelId, modelId);
  }

  Future<String?> getPanelImageModelId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPanelImageModelId);
  }

  Future<void> setPanelImageModelId(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPanelImageModelId, modelId);
  }

  Future<Map<String, dynamic>?> loadStoryGeneratorDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyStoryGeneratorDraft);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      AppLogger.storage.e('Failed to decode story generator draft', error: e);
      return null;
    }
  }

  Future<void> saveStoryGeneratorDraft(Map<String, dynamic> draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStoryGeneratorDraft, jsonEncode(draft));
  }
}

