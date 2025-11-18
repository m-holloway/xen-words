import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/story_generation_models.dart';
import '../utils/app_logger.dart';

class StoryStorageService {
  StoryStorageService._();

  static final StoryStorageService instance = StoryStorageService._();

  static const String _fileName = 'generated_stories.json';

  Future<File> _ensureFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode([]));
    }
    return file;
  }

  Future<List<GeneratedStoryRecord>> loadStories() async {
    try {
      final file = await _ensureFile();
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        return [];
      }
      final data = jsonDecode(contents) as List<dynamic>;
      return data
          .map((e) => GeneratedStoryRecord.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      AppLogger.storage.e('Failed to load saved stories', error: e);
      return [];
    }
  }

  Future<void> saveStory(GeneratedStoryRecord story) async {
    try {
      final file = await _ensureFile();
      final stories = await loadStories();
      final existingIndex = stories.indexWhere((s) => s.id == story.id);
      if (existingIndex >= 0) {
        stories[existingIndex] = story;
      } else {
        stories.insert(0, story);
      }
      final jsonList = stories.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
      AppLogger.storage.emoji('💾', 'Story saved locally (${story.id})');
    } catch (e) {
      AppLogger.storage.e('Failed to save story', error: e);
      rethrow;
    }
  }

  Future<void> deleteStory(String storyId) async {
    try {
      final file = await _ensureFile();
      final stories = await loadStories();
      final filtered = stories.where((s) => s.id != storyId).toList();
      await file.writeAsString(jsonEncode(filtered.map((e) => e.toJson()).toList()));
      AppLogger.storage.d('Deleted story $storyId');
    } catch (e) {
      AppLogger.storage.e('Failed to delete story', error: e);
      rethrow;
    }
  }

  Future<GeneratedStoryRecord?> getStoryById(String storyId) async {
    final stories = await loadStories();
    return stories.where((s) => s.id == storyId).firstOrNull;
  }

  Future<void> clearAll() async {
    final file = await _ensureFile();
    await file.writeAsString(jsonEncode([]));
  }
}

