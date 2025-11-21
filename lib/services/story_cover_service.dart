import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class StoryCoverService {
  StoryCoverService({ImagePicker? picker, ImageCropper? cropper})
    : _picker = picker ?? ImagePicker(),
      _cropper = cropper ?? ImageCropper();

  final ImagePicker _picker;
  final ImageCropper _cropper;

  Future<String?> pickAndStoreCover({
    required BuildContext context,
    required String storyId,
    String? existingCoverPath,
  }) async {
    final source = await _promptSource(context);
    if (source == null) return null;

    final capture = await _picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 3200,
      imageQuality: 92,
    );
    if (capture == null) return null;

    final cropped = await _cropper.cropImage(
      sourcePath: capture.path,
      aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 4),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop book cover',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
          showCropGrid: true,
          initAspectRatio: CropAspectRatioPreset.original,
        ),
        IOSUiSettings(
          title: 'Crop book cover',
          aspectRatioLockEnabled: true,
          aspectRatioPickerButtonHidden: true,
          rotateButtonsHidden: true,
        ),
      ],
    );
    if (cropped == null) {
      return null;
    }

    final storedPath = await _persistCoverFile(File(cropped.path), storyId);
    if (existingCoverPath != null) {
      await _deleteFile(existingCoverPath);
    }
    return storedPath;
  }

  Future<void> deleteCover(String? coverPath) async {
    if (coverPath == null) return;
    await _deleteFile(coverPath);
  }

  Future<ImageSource?> _promptSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
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
                  'Add book cover',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a portrait image so we can crop it into a 3:4 book cover. '
                  'Center the title or hero so it looks great on the shelf.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from library'),
                  subtitle: const Text('Browse saved art or downloads'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Use camera'),
                  subtitle: const Text('Snap a quick cover illustration'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String> _persistCoverFile(File file, String storyId) async {
    final directory = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${directory.path}/story_covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    final fileName =
        'cover_${storyId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destination = File('${coversDir.path}/$fileName');
    await file.copy(destination.path);
    return destination.path;
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
