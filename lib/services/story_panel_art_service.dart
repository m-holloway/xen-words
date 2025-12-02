import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'; // for compute
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/story_generation_models.dart';

class _PanelProcessingConfig {
  final String imagePath;
  final String outputDirPath;
  final int panelCount;

  _PanelProcessingConfig({
    required this.imagePath,
    required this.outputDirPath,
    required this.panelCount,
  });
}

Future<List<String>> _processPanelArt(_PanelProcessingConfig config) async {
  final file = File(config.imagePath);
  final bytes = await file.readAsBytes();
  final composite = img.decodeImage(bytes);
  if (composite == null) {
    throw StoryPanelArtException('We could not read that image file.');
  }

  // Fixed grid: always 4×4 (16 cells), matching the image generation prompt.
  // [panelCount] only controls how many slices we keep, not the grid geometry.
  const int cols = 4;
  const int rows = 4;
  const int maxCells = cols * rows;

  final int targetPanels = min(config.panelCount, maxCells);

  final cellW = composite.width ~/ cols;
  final cellH = composite.height ~/ rows;

  // Split and save
  final panelPaths = <String>[];
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      if (panelPaths.length >= targetPanels) {
        return panelPaths;
      }

      // Calculate rough center of the cell
      final cx = (c + 0.5) * cellW;
      final cy = (r + 0.5) * cellH;

      // Scan from center out to find content bounds inside this cell
      final bounds =
          _scanContentBounds(composite, cx.toInt(), cy.toInt(), cellW, cellH);

      final cropped = img.copyCrop(
        composite,
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height,
      );

      final outFile = File(
        '${config.outputDirPath}/panel_${panelPaths.length + 1}.jpg',
      );
      await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 95));
      panelPaths.add(outFile.path);
    }
  }
  return panelPaths;
}

// Helper struct
class _Rect {
  final int left, top, width, height;
  _Rect(this.left, this.top, this.width, this.height);
}

// Ray scan logic
_Rect _scanContentBounds(img.Image image, int cx, int cy, int cellW, int cellH) {
  const threshold = 60; // Black threshold
  const minRunLength = 5; // Ignore small noise
  
  bool isBlack(int x, int y) {
    if (x < 0 || x >= image.width || y < 0 || y >= image.height) return true;
    final p = image.getPixel(x, y);
    return (p.r + p.g + p.b) <= threshold; // Low brightness = black
  }

  // Helper: Scan in direction (dx, dy) until hit black run
  int scan(int startX, int startY, int dx, int dy, int maxDist) {
    int run = 0;
    for (int i = 0; i < maxDist; i++) {
      int x = startX + i * dx;
      int y = startY + i * dy;
      
      if (isBlack(x, y)) {
        run++;
        if (run >= minRunLength) {
          // Found edge at i - run
          return i - run; 
        }
      } else {
        run = 0; // Reset run if we see content
      }
    }
    return maxDist; // Hit cell boundary
  }

  // Scan limits (don't go beyond cell)
  final maxLeft = min(cx, cellW ~/ 2);
  final maxRight = min(image.width - cx, cellW ~/ 2);
  final maxUp = min(cy, cellH ~/ 2);
  final maxDown = min(image.height - cy, cellH ~/ 2);

  final dLeft = scan(cx, cy, -1, 0, maxLeft);
  final dRight = scan(cx, cy, 1, 0, maxRight);
  final dUp = scan(cx, cy, 0, -1, maxUp);
  final dDown = scan(cx, cy, 0, 1, maxDown);

  // Shave borders (2px safe)
  final shave = 2;
  final left = cx - dLeft + shave;
  final top = cy - dUp + shave;
  final right = cx + dRight - shave;
  final bottom = cy + dDown - shave;
  
  final width = max(1, right - left);
  final height = max(1, bottom - top);
  
  // Sanity check: If detected content is unreasonably small (e.g. < 5% of cell),
  // assume detection failed (e.g. dark image content) and fallback to full cell.
  // This prevents returning tiny/empty crops for dark panels.
  if (width < cellW * 0.05 || height < cellH * 0.05) {
     return _Rect(
       cx - cellW ~/ 2 + shave, 
       cy - cellH ~/ 2 + shave, 
       cellW - 2 * shave, 
       cellH - 2 * shave
     );
  }

  return _Rect(left, top, width, height);
}

/* REMOVED: _trimBlackBorders, _resolveGrid, _divisors */

class StoryPanelArtService {
  StoryPanelArtService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Process a panel art grid image and split it into individual panels.
  /// 
  /// This uses the same intelligent grid detection logic as the manual import flow.
  /// [gridImagePath] - Path to the grid image file
  /// [outputDir] - Directory where panel images should be saved
  /// [panelCount] - Expected number of panels in the grid
  /// 
  /// Returns a list of file paths for the extracted panel images.
  Future<List<String>> processPanelGrid({
    required String gridImagePath,
    required String outputDir,
    required int panelCount,
  }) async {
    // Use the same processing logic as manual import
    final rawPanelPaths = await compute(
      _processPanelArt,
      _PanelProcessingConfig(
        imagePath: gridImagePath,
        outputDirPath: outputDir,
        panelCount: panelCount,
      ),
    );
    return rawPanelPaths;
  }

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

    final batchDir = await _createBatchDirectory(storyId);
    
    // Check for upscale
    String processPath = capture.path;
    final upscaledPath = await _upscaleImageIfSmall(capture.path);
    if (upscaledPath != null) {
      processPath = upscaledPath;
      debugPrint('Upscaled panel art to $processPath');
    }

    // Run processing in a background isolate to prevent UI jank
    final rawPanelPaths = await compute(_processPanelArt, _PanelProcessingConfig(
      imagePath: processPath,
      outputDirPath: batchDir.path,
      panelCount: panelCount,
    ));

    File sourceFile = File(capture.path);
    if (upscaledPath != null) {
      sourceFile = File(upscaledPath);
    }

    final sheetPath = await _persistSheetFile(sourceFile, batchDir);
    
    // Clean up temp upscale file if it exists
    if (upscaledPath != null) {
       try { await File(upscaledPath).delete(); } catch (_) {}
    }

    // Allow user to select/confirm panels
    final selectedPaths = await _promptSelection(context, rawPanelPaths);
    if (selectedPaths == null || selectedPaths.isEmpty) {
      // User cancelled or selected nothing
      try {
        await batchDir.delete(recursive: true);
      } catch (_) {}
      return null;
    }

    if (existingArt != null) {
      await deletePanelArt(existingArt);
    }

    // Default assignments: Map 1:1 to first N panels
    final Map<int, String> initialAssignments = {};
    for (int i = 0; i < panelCount && i < selectedPaths.length; i++) {
      initialAssignments[i] = selectedPaths[i];
    }

    int estimatedCols = sqrt(panelCount).ceil();
    int estimatedRows = (panelCount / estimatedCols).ceil();

    return StoryPanelArtMetadata(
      columns: estimatedCols,
      rows: estimatedRows,
      panelImagePaths: selectedPaths,
      sheetImagePath: sheetPath,
      sheetImagePaths: [sheetPath],
      importedAt: DateTime.now(),
      assignments: initialAssignments,
    );
  }
  
  Future<String?> _upscaleImageIfSmall(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      
      // Decode image to get dimensions and frame
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      // Check if upscale is needed (if max dimension is < 2048)
      if (max(originalImage.width, originalImage.height) >= 2048) {
        originalImage.dispose();
        return null;
      }
      
      // Calculate scale to make the largest dimension 2048
      final double scale = 2048.0 / max(originalImage.width, originalImage.height);
      final int targetW = (originalImage.width * scale).round();
      final int targetH = (originalImage.height * scale).round();
      
      // Create recorder and canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()));
      
      // High quality scaling
      final paint = Paint()..filterQuality = FilterQuality.high;
      
      canvas.drawImageRect(
        originalImage,
        Rect.fromLTWH(0, 0, originalImage.width.toDouble(), originalImage.height.toDouble()),
        Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
        paint,
      );
      
      final picture = recorder.endRecording();
      final img = await picture.toImage(targetW, targetH);
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      
      // Cleanup
      originalImage.dispose();
      img.dispose();
      
      if (pngBytes == null) return null;
      
      final tempDir = await getTemporaryDirectory();
      final dest = File('${tempDir.path}/upscaled_${DateTime.now().millisecondsSinceEpoch}.png');
      await dest.writeAsBytes(pngBytes.buffer.asUint8List());
      
      return dest.path;
    } catch (e) {
      debugPrint('Error upscaling image: $e');
      return null; // Fallback to original
    }
  }

  Future<List<String>?> _promptSelection(
    BuildContext context,
    List<String> allPaths,
  ) {
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
      ...art.sheetImagePaths,
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
}

class StoryPanelArtException implements Exception {
  StoryPanelArtException(this.message);

  final String message;

  @override
  String toString() => message;
}

/* REMOVED: _PanelGrid */

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
