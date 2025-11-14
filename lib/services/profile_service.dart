import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/child_profile.dart';
import '../models/learning_progress.dart';
import '../utils/app_logger.dart';

/// Service for managing child profiles
class ProfileService {
  static const String _keyProfiles = 'child_profiles';
  static const String _keyActiveProfileId = 'active_profile_id';
  static const String _keyProgressPrefix = 'progress_'; // progress_{profileId}
  
  /// Generate a unique ID for a profile (public for external use)
  static String generateId() {
    return 'profile_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }
  
  /// Generate a unique ID for a profile (private instance method)
  String _generateId() {
    return generateId();
  }
  
  /// Load all profiles
  Future<List<ChildProfile>> loadProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString(_keyProfiles);
      
      if (profilesJson == null) {
        return [];
      }
      
      final List<dynamic> profilesList = jsonDecode(profilesJson);
      return profilesList
          .map((json) => ChildProfile.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.storage.e('Error loading profiles', error: e);
      return [];
    }
  }
  
  /// Save all profiles
  Future<void> saveProfiles(List<ChildProfile> profiles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = jsonEncode(
        profiles.map((p) => p.toJson()).toList(),
      );
      await prefs.setString(_keyProfiles, profilesJson);
      AppLogger.storage.d('Saved ${profiles.length} profiles');
    } catch (e) {
      AppLogger.storage.e('Error saving profiles', error: e);
      rethrow;
    }
  }
  
  /// Create a new profile
  Future<ChildProfile> createProfile({
    required String name,
    int? ageYears,
    String? emoji,
    int? colorIndex,
  }) async {
    final now = DateTime.now();
    final profiles = await loadProfiles();
    
    // Assign color and emoji
    final usedColors = profiles.map((p) => p.color.value).toSet();
    final availableColors = ProfileColors.available
        .where((c) => !usedColors.contains(c.value))
        .toList();
    
    final profile = ChildProfile(
      id: _generateId(),
      name: name,
      ageYears: ageYears,
      createdDate: now,
      lastActiveDate: now,
      color: colorIndex != null && colorIndex < ProfileColors.available.length
          ? ProfileColors.available[colorIndex]
          : (availableColors.isNotEmpty 
              ? availableColors.first 
              : ProfileColors.random()),
      emoji: emoji ?? ProfileEmojis.random(),
    );
    
    profiles.add(profile);
    await saveProfiles(profiles);
    
    AppLogger.ui.i('Created profile: ${profile.name} (${profile.id})');
    return profile;
  }
  
  /// Update a profile
  Future<void> updateProfile(ChildProfile profile) async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((p) => p.id == profile.id);
    
    if (index == -1) {
      throw Exception('Profile not found: ${profile.id}');
    }
    
    profiles[index] = profile.copyWith(lastActiveDate: DateTime.now());
    await saveProfiles(profiles);
    
    AppLogger.ui.d('Updated profile: ${profile.name}');
  }
  
  /// Delete a profile and its progress
  Future<void> deleteProfile(String profileId) async {
    if (profileId == 'guest') {
      throw Exception('Cannot delete guest profile');
    }
    
    // Load profiles
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == profileId);
    await saveProfiles(profiles);
    
    // Delete associated progress
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyProgressPrefix$profileId');
    
    AppLogger.ui.i('Deleted profile: $profileId');
  }
  
  /// Get active profile ID
  Future<String?> getActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveProfileId);
  }
  
  /// Set active profile
  Future<void> setActiveProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveProfileId, profileId);
    
    // Update last active date if not guest
    if (profileId != 'guest') {
      final profiles = await loadProfiles();
      final index = profiles.indexWhere((p) => p.id == profileId);
      if (index != -1) {
        profiles[index] = profiles[index].copyWith(
          lastActiveDate: DateTime.now(),
        );
        await saveProfiles(profiles);
      }
    }
    
    AppLogger.ui.d('Set active profile: $profileId');
  }
  
  /// Get active profile
  Future<ChildProfile?> getActiveProfile() async {
    final profileId = await getActiveProfileId();
    if (profileId == null) return null;
    
    if (profileId == 'guest') {
      return ChildProfile.guest();
    }
    
    final profiles = await loadProfiles();
    return profiles.cast<ChildProfile?>().firstWhere(
      (p) => p?.id == profileId,
      orElse: () => null,
    );
  }
  
  /// Load progress for a specific profile
  Future<LearningProgress?> loadProgress(String profileId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final progressJson = prefs.getString('$_keyProgressPrefix$profileId');
      
      if (progressJson == null) {
        return null;
      }
      
      final data = jsonDecode(progressJson) as Map<String, dynamic>;
      return LearningProgress.fromJson(data);
    } catch (e) {
      AppLogger.storage.e('Error loading progress for $profileId', error: e);
      return null;
    }
  }
  
  /// Save progress for a specific profile
  Future<void> saveProgress(String profileId, LearningProgress progress) async {
    if (profileId == 'guest') {
      // Don't save guest progress
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final progressJson = jsonEncode(progress.toJson());
      await prefs.setString('$_keyProgressPrefix$profileId', progressJson);
      AppLogger.storage.d('Saved progress for profile: $profileId');
    } catch (e) {
      AppLogger.storage.e('Error saving progress for $profileId', error: e);
      rethrow;
    }
  }
  
  /// Clear all profile data (for testing)
  Future<void> clearAllProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get all profiles to delete their progress
    final profiles = await loadProfiles();
    for (final profile in profiles) {
      await prefs.remove('$_keyProgressPrefix${profile.id}');
    }
    
    // Clear profiles list and active profile
    await prefs.remove(_keyProfiles);
    await prefs.remove(_keyActiveProfileId);
    
    AppLogger.storage.i('Cleared all profiles and progress');
  }
  
  /// Check if any profiles exist
  Future<bool> hasProfiles() async {
    final profiles = await loadProfiles();
    return profiles.isNotEmpty;
  }
  
  /// Get profile count
  Future<int> getProfileCount() async {
    final profiles = await loadProfiles();
    return profiles.length;
  }
  
  /// Check if in guest mode
  Future<bool> isGuestMode() async {
    final activeId = await getActiveProfileId();
    return activeId == 'guest';
  }
  
  /// Set guest mode
  Future<void> setGuestMode() async {
    await setActiveProfile('guest');
  }
  
  /// Add a profile (wrapper for createProfile)
  Future<void> addProfile(ChildProfile profile) async {
    final profiles = await loadProfiles();
    profiles.add(profile);
    await saveProfiles(profiles);
    AppLogger.ui.i('Added profile: ${profile.name} (${profile.id})');
  }
  
  /// Load progress for a specific profile (alias for loadProgress)
  Future<LearningProgress?> loadProgressForProfile(String profileId) async {
    return loadProgress(profileId);
  }
}

