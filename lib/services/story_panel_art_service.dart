import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/story_generation_models.dart';

class StoryPanelArtService {
  StoryPanelArtService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<StoryPanelArtMetadata?> pickAndStorePanelArt({
    required BuildContext context,
    required String storyId,
    required int panelCount,
    StoryPanelArtMetadata? existingArt,
  }) async {
    if (panelCount <= 0) {
      throw StoryPanelArtException(
        'This story needs at least one narration paragraph before art can be imported.',
      );
    }

    final confirm = await _promptSource(context, panelCount);
    if (confirm != true) {
      return null;
    }

    final capture = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 95,
    );
    if (capture == null) {
      return null;
    }

    final bytes = await capture.readAsBytes();
    final composite = img.decodeImage(bytes);
    if (composite == null) {
      throw StoryPanelArtException('We could not read that image file.');
    }

    final grid = _resolveGrid(composite.width, composite.height, panelCount);
    if (grid == null) {
      throw StoryPanelArtException(
        'Unable to detect a clean square grid. Make sure the collage uses equally sized panels without cropping.',
      );
    }
    if (grid.totalPanels < panelCount) {
      throw StoryPanelArtException(
        'The collage only contains ${grid.totalPanels} panels but this story needs $panelCount.',
      );
    }

    final batchDir = await _createBatchDirectory(storyId);
    final sheetPath = await _persistSheetFile(File(capture.path), batchDir);
    final panelPaths = await _splitAndSavePanels(
      composite,
      batchDir,
      panelCount,
      grid,
    );

    if (existingArt != null) {
      await deletePanelArt(existingArt);
    }

    return StoryPanelArtMetadata(
      columns: grid.columns,
      rows: grid.rows,
      panelImagePaths: panelPaths,
      sheetImagePath: sheetPath,
      importedAt: DateTime.now(),
    );
  }

  Future<void> deletePanelArt(StoryPanelArtMetadata? art) async {
    if (art == null) return;
    final files = [
      ...art.panelImagePaths,
      art.sheetImagePath,
    ];
    for (final path in files) {
      if (path.isEmpty) continue;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    try {
      final dir = File(art.sheetImagePath).parent;
      if (await dir.exists()) {
        final remaining = await dir.list().isEmpty;
        if (remaining) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  Future<bool?> _promptSource(BuildContext context, int panelCount) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import scene-by-scene art',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a square collage that contains $panelCount panels laid out left to right, top to bottom. '
                  'We will split each square into artwork for that paragraph.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from library'),
                  subtitle: const Text('Select the AI-generated comic grid'),
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Directory> _createBatchDirectory(String storyId) async {
    final docs = await getApplicationDocumentsDirectory();
    final base = Directory('${docs.path}/story_panels/$storyId');
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    final batchDir = Directory(
      '${base.path}/${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!await batchDir.exists()) {
      await batchDir.create(recursive: true);
    }
    return batchDir;
  }

  Future<String> _persistSheetFile(File source, Directory target) async {
    final destination = File(
      '${target.path}/sheet_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await source.copy(destination.path);
    return destination.path;
  }

  Future<List<String>> _splitAndSavePanels(
    img.Image composite,
    Directory batchDir,
    int panelCount,
    _PanelGrid grid,
  ) async {
    final panelPaths = <String>[];
    for (int row = 0; row < grid.rows; row++) {
      for (int col = 0; col < grid.columns; col++) {
        if (panelPaths.length >= panelCount) {
          return panelPaths;
        }
        final offsetX = col * grid.panelSize;
        final offsetY = row * grid.panelSize;
        final cropped = img.copyCrop(
          composite,
          x: offsetX,
          y: offsetY,
          width: grid.panelSize,
          height: grid.panelSize,
        );
        final file = File(
          '${batchDir.path}/panel_${panelPaths.length + 1}.jpg',
        );
        await file.writeAsBytes(img.encodeJpg(cropped, quality: 95));
        panelPaths.add(file.path);
      }
    }
    return panelPaths;
  }

  _PanelGrid? _resolveGrid(int width, int height, int panelCount) {
    final candidates = <_PanelGrid>[];
    for (final columns in _divisors(width)) {
      final panelSize = width ~/ columns;
      if (panelSize == 0) continue;
      if (height % panelSize != 0) continue;
      final rows = height ~/ panelSize;
      if (rows <= 0) continue;
      final total = rows * columns;
      if (total <= 0) continue;
      candidates.add(
        _PanelGrid(
          columns: columns,
          rows: rows,
          panelSize: panelSize,
          totalPanels: total,
        ),
      );
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => a.totalPanels.compareTo(b.totalPanels));
    for (final grid in candidates) {
      if (grid.totalPanels >= panelCount) {
        return grid;
      }
    }
    return candidates.last;
  }

  List<int> _divisors(int value) {
    final divisors = <int>{};
    final limit = sqrt(value).floor();
    for (int i = 1; i <= limit; i++) {
      if (value % i != 0) continue;
      divisors.add(i);
      divisors.add(value ~/ i);
    }
    final list = divisors.toList()..sort();
    return list;
  }
}

class StoryPanelArtException implements Exception {
  StoryPanelArtException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PanelGrid {
  const _PanelGrid({
    required this.columns,
    required this.rows,
    required this.panelSize,
    required this.totalPanels,
  });

  final int columns;
  final int rows;
  final int panelSize;
  final int totalPanels;
}

