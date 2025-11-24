import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import '../models/child_profile.dart';
import '../models/story_world_models.dart';
import '../services/profile_service.dart';
import '../services/story_world_service.dart';
import '../services/story_world_art_service.dart';
import 'story_coach_screen.dart';
import 'story_world_explorer_screen.dart';
import '../utils/app_logger.dart';

/// Hub for the child's Story World: characters (Wonder Cast),
/// things, places, and drawings.
class StoryWorldScreen extends StatefulWidget {
  const StoryWorldScreen({super.key});

  @override
  State<StoryWorldScreen> createState() => _StoryWorldScreenState();
}

class _StoryWorldScreenState extends State<StoryWorldScreen> {
  final StoryWorldService _worldService = StoryWorldService.instance;
  final ProfileService _profileService = ProfileService();
  final ImagePicker _imagePicker = ImagePicker();

  String? _profileId;
  String? _profileName;
  bool _isLoading = true;
  List<StoryCharacterEntity> _characters = const [];
  List<StoryDrawingEntity> _drawings = const [];
  List<StoryThingEntity> _things = const [];
  List<StoryPlaceEntity> _places = const [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    try {
      final activeId = await _profileService.getActiveProfileId();
      final profiles = await _profileService.loadProfiles();
      ChildProfile? activeProfile;
      if (activeId != null) {
        activeProfile = profiles.where((p) => p.id == activeId).firstOrNull;
      }
      final profileId = activeProfile?.id ?? 'guest';
      final world = await _worldService.loadWorld(profileId);
      if (!mounted) return;
      setState(() {
        _profileId = profileId;
        _profileName = activeProfile?.name;
        _characters = world.characters.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _drawings = world.drawings.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _things = world.things.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _places = world.places.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });
    } catch (e) {
      AppLogger.system.e('Failed to load Story World', error: e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshWorld() async {
    final id = _profileId;
    if (id == null) return;
    final world = await _worldService.loadWorld(id);
    if (!mounted) return;
    setState(() {
      _characters = world.characters.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _drawings = world.drawings.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _things = world.things.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _places = world.places.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
  }

  Future<void> _createCharacter() async {
    final profileId = _profileId;
    if (profileId == null) return;

    final nameController = TextEditingController(
      text: _profileName != null && _profileName!.isNotEmpty
          ? 'The Amazing ${_profileName![0].toUpperCase()}${_profileName!.substring(1)}'
          : '',
    );
    final summaryController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create a Story Friend'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Character name',
                  hintText: 'The Amazing AZ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(
                  labelText: 'Short description (optional)',
                  hintText:
                      'A glittery superhero who turns bad days into sparkles.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (created != true) return;

    final name = nameController.text.trim();
    final summary = summaryController.text.trim().isEmpty
        ? null
        : summaryController.text.trim();

    await _worldService.createCharacter(
      profileId: profileId,
      displayName: name,
      summary: summary,
      inspiredByProfileId: _profileId == 'guest' ? null : _profileId,
    );
    await _refreshWorld();
  }

  Future<void> _createThing() async {
    final profileId = _profileId;
    if (profileId == null) return;

    final nameController = TextEditingController();
    final summaryController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create a Story Thing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Thing name',
                  hintText: 'Rainbow Wand',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(
                  labelText: 'What makes it special?',
                  hintText: 'Describe how it looks or works.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (created != true) return;

    final now = DateTime.now();
    final thing = StoryThingEntity(
      id: 'temp_${now.millisecondsSinceEpoch}',
      displayName: nameController.text.trim(),
      summary: summaryController.text.trim().isEmpty
          ? null
          : summaryController.text.trim(),
      tags: const [],
      rules: null,
      imagePath: null,
      drawingIds: const [],
      createdAt: now,
      updatedAt: now,
    );
    await _worldService.upsertThing(
      profileId: profileId,
      thing: thing,
    );
    await _refreshWorld();
  }

  Future<void> _createPlace() async {
    final profileId = _profileId;
    if (profileId == null) return;

    final nameController = TextEditingController();
    final summaryController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create a Story Place'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Place name',
                  hintText: 'Cozy Cloud Castle',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(
                  labelText: 'What is it like?',
                  hintText: 'Describe what it looks and feels like.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (created != true) return;

    final now = DateTime.now();
    final place = StoryPlaceEntity(
      id: 'temp_${now.millisecondsSinceEpoch}',
      displayName: nameController.text.trim(),
      summary: summaryController.text.trim().isEmpty
          ? null
          : summaryController.text.trim(),
      tags: const [],
      placeType: null,
      imagePath: null,
      drawingIds: const [],
      createdAt: now,
      updatedAt: now,
    );
    await _worldService.upsertPlace(
      profileId: profileId,
      place: place,
    );
    await _refreshWorld();
  }

  Future<void> _editThing(StoryThingEntity thing) async {
    final profileId = _profileId;
    if (profileId == null) return;

    final nameController = TextEditingController(
      text: thing.displayName ?? '',
    );
    final summaryController = TextEditingController(
      text: thing.summary ?? '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Story Thing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Thing name',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(
                  labelText: 'What makes it special?',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete Story Thing?'),
            content: const Text(
              'This will remove the thing from Story World, but will not '
              'delete any stories.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
      if (confirm == true) {
        await _worldService.deleteThing(
          profileId: profileId,
          thingId: thing.id,
        );
        await _refreshWorld();
      }
      return;
    }

    if (result == 'save') {
      final updated = thing.copyWith(
        displayName: nameController.text.trim().isEmpty
            ? thing.displayName
            : nameController.text.trim(),
        summary: summaryController.text.trim().isEmpty
            ? null
            : summaryController.text.trim(),
        updatedAt: DateTime.now(),
      );
      await _worldService.upsertThing(
        profileId: profileId,
        thing: updated,
      );
      await _refreshWorld();
    }
  }

  Future<void> _editPlace(StoryPlaceEntity place) async {
    final profileId = _profileId;
    if (profileId == null) return;

    final nameController = TextEditingController(
      text: place.displayName ?? '',
    );
    final summaryController = TextEditingController(
      text: place.summary ?? '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Story Place'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Place name',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(
                  labelText: 'What is it like?',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete Story Place?'),
            content: const Text(
              'This will remove the place from Story World, but will not '
              'delete any stories.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
      if (confirm == true) {
        await _worldService.deletePlace(
          profileId: profileId,
          placeId: place.id,
        );
        await _refreshWorld();
      }
      return;
    }

    if (result == 'save') {
      final updated = place.copyWith(
        displayName: nameController.text.trim().isEmpty
            ? place.displayName
            : nameController.text.trim(),
        summary: summaryController.text.trim().isEmpty
            ? null
            : summaryController.text.trim(),
        updatedAt: DateTime.now(),
      );
      await _worldService.upsertPlace(
        profileId: profileId,
        place: updated,
      );
      await _refreshWorld();
    }
  }

  Future<void> _addDrawing() async {
    final profileId = _profileId;
    if (profileId == null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a picture of a drawing'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text('Choose from photos'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxHeight: 2048,
        maxWidth: 2048,
      );
      if (picked == null) return;

      final docs = await getApplicationDocumentsDirectory();
      final drawingsDir = Directory('${docs.path}/story_drawings');
      if (!await drawingsDir.exists()) {
        await drawingsDir.create(recursive: true);
      }
      final fileName =
          'drawing_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final target = File('${drawingsDir.path}/$fileName');
      await File(picked.path).copy(target.path);

      await _worldService.createDrawing(
        profileId: profileId,
        imagePath: target.path,
        captureSource: source == ImageSource.camera ? 'camera' : 'gallery',
        createdByProfileId: profileId == 'guest' ? null : profileId,
      );
      await _refreshWorld();
    } catch (e) {
      AppLogger.system.e('Failed to add drawing', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save drawing. Please try again.')),
      );
    }
  }

  Future<void> _editDrawing(StoryDrawingEntity drawing) async {
    final profileId = _profileId;
    if (profileId == null) return;

    final nameController = TextEditingController(
      text: drawing.displayName ?? '',
    );
    final summaryController = TextEditingController(
      text: drawing.summary ?? '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit drawing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(drawing.imagePath),
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'Rainbow Wand sketch',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Any notes about this drawing',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete drawing?'),
            content: const Text(
              'This will remove the drawing from Story World. It may no longer '
              'appear as inspiration for characters or scenes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
      if (confirm == true) {
        await _worldService.deleteDrawing(
          profileId: profileId,
          drawingId: drawing.id,
        );
        await _refreshWorld();
      }
      return;
    }

    if (result == 'save') {
      final updated = drawing.copyWith(
        displayName: nameController.text.trim().isEmpty
            ? null
            : nameController.text.trim(),
        summary: summaryController.text.trim().isEmpty
            ? null
            : summaryController.text.trim(),
        updatedAt: DateTime.now(),
      );
      await _worldService.upsertDrawing(
        profileId: profileId,
        drawing: updated,
      );
      await _refreshWorld();
    }
  }

  void _openCharacterDetail(StoryCharacterEntity character) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryCharacterDetailScreen(
          character: character,
          profileId: _profileId ?? 'guest',
        ),
      ),
    ).then((_) => _refreshWorld());
  }

  @override
  Widget build(BuildContext context) {
    final name = _profileName ?? 'your child';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Story World',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Wonder Cast & drawings for $name',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCharacter,
        icon: const Icon(Icons.add),
        label: const Text('New Story Friend'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshWorld,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _buildIntroCard(),
                  const SizedBox(height: 16),
                  _buildCharactersSection(),
                  const SizedBox(height: 24),
                  _buildDrawingsSection(),
                  const SizedBox(height: 24),
                  _buildThingsSection(),
                  const SizedBox(height: 24),
                  _buildPlacesSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildIntroCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.auto_awesome,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome to Story World',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Create Story Friends, special things, and places that can '
                    'reappear across bedtime adventures.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StoryCoachScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.psychology_alt_outlined),
                      label: const Text('Open Story Coach'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        if (_profileId == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StoryWorldExplorerScreen(
                              profileId: _profileId!,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Explore Story World'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharactersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Wonder Cast',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            TextButton.icon(
              onPressed: _createCharacter,
              icon: const Icon(Icons.add),
              label: const Text('Add Friend'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_characters.isEmpty)
          const Text(
            'No Story Friends yet. Create one to bring your child into the story.',
          )
        else
          Column(
            children: _characters
                .map(
                  (character) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CharacterCard(
                      character: character,
                      onTap: () => _openCharacterDetail(character),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildDrawingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My Drawings',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            TextButton.icon(
              onPressed: _addDrawing,
              icon: const Icon(Icons.brush),
              label: const Text('Add Drawing'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_drawings.isEmpty)
          const Text(
            'Snap a photo of your child’s art to bring it into their Story World.',
          )
        else
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _drawings.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final drawing = _drawings[index];
                return GestureDetector(
                  onTap: () => _editDrawing(drawing),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(drawing.imagePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                          if (drawing.displayName != null &&
                              drawing.displayName!.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 8,
                                ),
                                color: Colors.black.withOpacity(0.45),
                                child: Text(
                                  drawing.displayName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildThingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Story Things',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            TextButton.icon(
              onPressed: _createThing,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Add Thing'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_things.isEmpty)
          const Text(
            'Save special objects like wands, toys, or tools so they can '
            'reappear across stories.',
          )
        else
          Column(
            children: _things
                .map(
                  (thing) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => _editThing(thing),
                      child: _SimpleEntityCard(
                        icon: Icons.auto_fix_high,
                        title: thing.displayName ?? 'Story Thing',
                        subtitle: thing.summary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildPlacesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Story Places',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            TextButton.icon(
              onPressed: _createPlace,
              icon: const Icon(Icons.landscape_outlined),
              label: const Text('Add Place'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_places.isEmpty)
          const Text(
            'Capture magical worlds and cozy spots your child loves to visit '
            'in their stories.',
          )
        else
          Column(
            children: _places
                .map(
                  (place) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => _editPlace(place),
                      child: _SimpleEntityCard(
                        icon: Icons.landscape_outlined,
                        title: place.displayName ?? 'Story Place',
                        subtitle: place.summary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.onTap,
  });

  final StoryCharacterEntity character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);
    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withOpacity(0.4),
              theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.person,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.displayName ?? 'Unnamed Story Friend',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (character.summary != null &&
                        character.summary!.isNotEmpty)
                      Text(
                        character.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleEntityCard extends StatelessWidget {
  const _SimpleEntityCard({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(14);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: theme.colorScheme.surface,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail page for a single Story Friend (character).
///
/// This focuses on basic fields for now; later phases can enrich it with
/// story links, traits editing, and graph-powered views.
class StoryCharacterDetailScreen extends StatelessWidget {
  const StoryCharacterDetailScreen({
    super.key,
    required this.character,
    required this.profileId,
  });

  final StoryCharacterEntity character;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    return _StoryCharacterDetailBody(
      initialCharacter: character,
      profileId: profileId,
    );
  }
}

class _StoryCharacterDetailBody extends StatefulWidget {
  const _StoryCharacterDetailBody({
    required this.initialCharacter,
    required this.profileId,
  });

  final StoryCharacterEntity initialCharacter;
  final String profileId;

  @override
  State<_StoryCharacterDetailBody> createState() =>
      _StoryCharacterDetailBodyState();
}

class _StoryCharacterDetailBodyState
    extends State<_StoryCharacterDetailBody> {
  final StoryWorldService _worldService = StoryWorldService.instance;
  final StoryWorldArtService _artService = StoryWorldArtService();
  final ImagePicker _imagePicker = ImagePicker();
  final ImageCropper _imageCropper = ImageCropper();

  StoryCharacterEntity? _character;
  List<StoryDrawingEntity> _drawings = const [];
  StoryDrawingEntity? _attachedDrawing;
  bool _isGeneratingArt = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final world = await _worldService.loadWorld(widget.profileId);
      final latest =
          world.characters[widget.initialCharacter.id] ?? widget.initialCharacter;
      final drawings = world.drawings.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      StoryDrawingEntity? attached;
      if (latest.drawingIds.isNotEmpty) {
        attached = world.drawings[latest.drawingIds.first];
      }
      if (!mounted) return;
      setState(() {
        _character = latest;
        _drawings = drawings;
        _attachedDrawing = attached;
      });
    } catch (e) {
      AppLogger.system.e(
        'Failed to load character detail for ${widget.initialCharacter.id}',
        error: e,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _attachDrawing(StoryDrawingEntity drawing) async {
    final current = _character;
    if (current == null) return;
    final ids = <String>{drawing.id, ...current.drawingIds}.toList();
    final updated = current.copyWith(
      drawingIds: ids,
      updatedAt: DateTime.now(),
    );
    await _worldService.upsertCharacter(
      profileId: widget.profileId,
      character: updated,
    );
    if (!mounted) return;
    setState(() {
      _character = updated;
      _attachedDrawing = drawing;
    });
  }

  Future<void> _chooseDrawing() async {
    if (_drawings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a drawing in My Story World first.'),
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<StoryDrawingEntity>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: _drawings.map((drawing) {
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(drawing.imagePath),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
                title: Text(
                  drawing.displayName?.isNotEmpty == true
                      ? drawing.displayName!
                      : 'Drawing',
                ),
                onTap: () => Navigator.of(context).pop(drawing),
              );
            }).toList(),
          ),
        );
      },
    );

    if (chosen != null) {
      await _attachDrawing(chosen);
    }
  }

  Future<void> _generatePortrait() async {
    final current = _character;
    if (current == null || _isGeneratingArt) return;
    setState(() {
      _isGeneratingArt = true;
    });
    try {
      final updated = await _artService.generateCharacterPortrait(
        profileId: widget.profileId,
        character: current,
        referenceDrawing: _attachedDrawing,
      );
      if (!mounted) return;
      setState(() {
        _character = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Character picture created!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create picture: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingArt = false;
        });
      }
    }
  }

  Widget _buildRealPhotoSection(
    StoryCharacterEntity character,
    ThemeData theme,
  ) {
    final hasPhoto = character.realPhotoPath != null &&
        character.realPhotoPath!.trim().isNotEmpty;
    final buttonLabel =
        hasPhoto ? 'Change real photo' : 'Attach real photo';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Real-life photo (optional)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            TextButton.icon(
              onPressed: _pickRealPhoto,
              icon: const Icon(Icons.photo_camera_back_outlined),
              label: Text(buttonLabel),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (hasPhoto)
          GestureDetector(
            onTap: () => _showFullScreenImage(character.realPhotoPath!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(character.realPhotoPath!),
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color: theme.colorScheme.surfaceVariant,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
          )
        else
          const Text(
            'You can attach a real photo of the person this friend is based on. '
            'We\'ll use it as a gentle visual reference when creating art.',
          ),
      ],
    );
  }

  Future<void> _pickRealPhoto() async {
    final profileId = widget.profileId;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text('Choose from photos'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked == null) return;

      // Let the parent crop the photo to the person of interest.
      final cropped = await _imageCropper.cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 92,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop photo',
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
            hideBottomControls: false,
            showCropGrid: true,
          ),
          IOSUiSettings(
            title: 'Crop photo',
            aspectRatioLockEnabled: false,
          ),
        ],
      );
      if (cropped == null) return;

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/story_photos');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final fileName =
          'photo_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      final target = File('${dir.path}/$fileName');
      await File(cropped.path).copy(target.path);

      final current = _character ?? widget.initialCharacter;
      final updated = current.copyWith(
        realPhotoPath: target.path,
        updatedAt: DateTime.now(),
      );
      await _worldService.upsertCharacter(
        profileId: profileId,
        character: updated,
      );
      if (!mounted) return;
      setState(() {
        _character = updated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not attach photo: $e'),
        ),
      );
    }
  }

  void _showFullScreenImage(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(imagePath: path),
      ),
    );
  }

  Future<void> _editDetails() async {
    final current = _character ?? widget.initialCharacter;
    final nameController = TextEditingController(
      text: current.displayName ?? '',
    );
    final summaryController = TextEditingController(
      text: current.summary ?? '',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Story Friend'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: summaryController,
                decoration: const InputDecoration(
                  labelText: 'Short description',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == 'save') {
      final updated = current.copyWith(
        displayName: nameController.text.trim().isEmpty
            ? current.displayName
            : nameController.text.trim(),
        summary: summaryController.text.trim().isEmpty
            ? null
            : summaryController.text.trim(),
        updatedAt: DateTime.now(),
      );
      await _worldService.upsertCharacter(
        profileId: widget.profileId,
        character: updated,
      );
      if (!mounted) return;
      setState(() {
        _character = updated;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final current = _character ?? widget.initialCharacter;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Story Friend?'),
          content: const Text(
            'This will remove the Story Friend from My Story World, but will '
            'not delete any stories where they appear.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm == true) {
      await _worldService.deleteCharacter(
        profileId: widget.profileId,
        characterId: current.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // Return to Story World list
    }
  }

  @override
  Widget build(BuildContext context) {
    final character = _character ?? widget.initialCharacter;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(character.displayName ?? 'Story Friend'),
        actions: [
          IconButton(
            tooltip: 'Edit details',
            icon: const Icon(Icons.edit),
            onPressed: _editDetails,
          ),
          IconButton(
            tooltip: 'Delete Story Friend',
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDelete,
          ),
          TextButton.icon(
            onPressed: _isGeneratingArt ? null : _generatePortrait,
            icon: _isGeneratingArt
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_isGeneratingArt ? 'Painting…' : 'Create picture'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GestureDetector(
                  onTap: character.heroPortraitPath != null
                      ? () => _showFullScreenImage(
                            character.heroPortraitPath!,
                          )
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primaryContainer.withOpacity(0.6),
                          theme.colorScheme.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 90,
                            height: 120,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: character.heroPortraitPath != null
                                  ? Image.file(
                                      File(character.heroPortraitPath!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.person,
                                        color: theme.colorScheme.primary,
                                        size: 40,
                                      ),
                                    )
                                  : Icon(
                                      Icons.person,
                                      color: theme.colorScheme.primary,
                                      size: 40,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  character.displayName ?? 'Story Friend',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                                if (character.summary != null &&
                                    character.summary!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      character.summary!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildRealPhotoSection(character, theme),
                const SizedBox(height: 24),
                if (_attachedDrawing != null) ...[
                  const Text(
                    'Drawing inspiration',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(_attachedDrawing!.imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _chooseDrawing,
                    icon: const Icon(Icons.switch_access_shortcut),
                    label: const Text('Change drawing'),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  TextButton.icon(
                    onPressed: _chooseDrawing,
                    icon: const Icon(Icons.brush),
                    label: const Text('Attach a drawing as inspiration'),
                  ),
                  const SizedBox(height: 24),
                ],
                const Text(
                  'Soon this page will also show stories, scenes, and art '
                  'where this Story Friend appears, plus traits and powers you '
                  'discover together.',
                ),
              ],
            ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image,
              color: Colors.white70,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}



