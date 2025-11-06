import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

/// Service for managing app preferences
class PreferencesService {
  static const String _keyCurrentWeek = 'current_week';
  static const String _keyAutoAdvanceEnabled = 'auto_advance_enabled';
  static const String _keyAdvanceDayOfWeek = 'advance_day_of_week';
  static const String _keyWordsPerWeek = 'words_per_week';
  static const String _keyLastAdvanceDate = 'last_advance_date';

  /// Load settings from preferences
  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final currentWeek = prefs.getInt(_keyCurrentWeek) ?? 1;
    final autoAdvanceEnabled = prefs.getBool(_keyAutoAdvanceEnabled) ?? true;
    final advanceDayOfWeek = prefs.getInt(_keyAdvanceDayOfWeek) ?? 0; // Sunday
    final wordsPerWeek = prefs.getInt(_keyWordsPerWeek) ?? 2;
    
    DateTime? lastAdvanceDate;
    final lastAdvanceTimestamp = prefs.getInt(_keyLastAdvanceDate);
    if (lastAdvanceTimestamp != null) {
      lastAdvanceDate = DateTime.fromMillisecondsSinceEpoch(lastAdvanceTimestamp);
    }
    
    var settings = AppSettings(
      currentWeek: currentWeek,
      autoAdvanceEnabled: autoAdvanceEnabled,
      advanceDayOfWeek: advanceDayOfWeek,
      wordsPerWeek: wordsPerWeek,
      lastAdvanceDate: lastAdvanceDate,
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
    
    if (settings.lastAdvanceDate != null) {
      await prefs.setInt(
        _keyLastAdvanceDate,
        settings.lastAdvanceDate!.millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_keyLastAdvanceDate);
    }
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
}

