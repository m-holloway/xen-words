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

    // Trim solid black borders before processing
    final trimmed = _trimBlackBorders(composite);

    final grid = _resolveGrid(trimmed.width, trimmed.height, panelCount);
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
    final rawPanelPaths = await _splitAndSavePanels(
      trimmed, // Use trimmed image
      batchDir,
      grid.totalPanels,
      grid,
    );

    // Allow user to select/confirm panels
    final selectedPaths = await _promptSelection(context, rawPanelPaths);
    if (selectedPaths == null || selectedPaths.isEmpty) {
      // User cancelled or selected nothing
      // Cleanup batch dir since we are aborting
      try {
        await batchDir.delete(recursive: true);
      } catch (_) {}
      return null;
    }

    if (existingArt != null) {
      await deletePanelArt(existingArt);
    }

    // Default assignments: Map 1:1 to first N panels
    // We store ALL selected panels in panelImagePaths (the pool)
    // And create initial assignments for available slots
    final Map<int, String> initialAssignments = {};
    for (int i = 0; i < panelCount && i < selectedPaths.length; i++) {
      initialAssignments[i] = selectedPaths[i];
    }

    return StoryPanelArtMetadata(
      columns: grid.columns,
      rows: grid.rows,
      panelImagePaths: selectedPaths,
      sheetImagePath: sheetPath,
      importedAt: DateTime.now(),
      assignments: initialAssignments,
    );
  }

  Future<List<String>?> _promptSelection(
    BuildContext context,
    List<String> allPaths,
  ) {
    // If only 1 panel or very few, maybe skip?
    // User request: "select which panels will be imported (defaulted to all)"
    // We show a dialog grid.
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PanelSelectionDialog(allPaths: allPaths),
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

  img.Image _trimBlackBorders(img.Image image) {
    // Determine bounding box of non-black content
    int minX = image.width;
    int maxX = 0;
    int minY = image.height;
    int maxY = 0;

    bool foundContent = false;

    // Simple threshold for "black" - sum of RGB channels < 15 (allows for slight compression noise)
    const threshold = 15;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        if (pixel.r + pixel.g + pixel.b > threshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          foundContent = true;
        }
      }
    }

    if (!foundContent) {
      return image; // Return original if fully black or empty
    }

    // If bounds cover the whole image, no trimming needed
    if (minX == 0 && minY == 0 && maxX == image.width - 1 && maxY == image.height - 1) {
      return image;
    }

    // Crop to the bounding box
    // Width/Height is exclusive max - min + 1
    return img.copyCrop(
      image,
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
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

class _PanelSelectionDialog extends StatefulWidget {
  const _PanelSelectionDialog({required this.allPaths});

  final List<String> allPaths;

  @override
  State<_PanelSelectionDialog> createState() => _PanelSelectionDialogState();
}

class _PanelSelectionDialogState extends State<_PanelSelectionDialog> {
  late final Set<String> _selectedPaths;

  @override
  void initState() {
    super.initState();
    _selectedPaths = widget.allPaths.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select panels to import'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 100,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: widget.allPaths.length,
          itemBuilder: (context, index) {
            final path = widget.allPaths[index];
            final isSelected = _selectedPaths.contains(path);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedPaths.remove(path);
                  } else {
                    _selectedPaths.add(path);
                  }
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Opacity(
                      opacity: isSelected ? 1.0 : 0.4,
                      child: Image.file(
                        File(path),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selectedPaths.isEmpty
              ? null
              : () {
                  // Return sorted by original index to preserve order
                  final result = widget.allPaths
                      .where((p) => _selectedPaths.contains(p))
                      .toList();
                  Navigator.of(context).pop(result);
                },
          child: Text('Import (${_selectedPaths.length})'),
        ),
      ],
    );
  }
}

