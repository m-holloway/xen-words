import 'package:flutter/material.dart';
import '../models/child_profile.dart';
import '../services/profile_service.dart';
import '../widgets/profile_editor_dialog.dart';
import '../utils/app_logger.dart';

/// Screen for selecting which child profile to use.
/// Displays all profiles in a kid-friendly grid with option for guest mode.
class ProfileSelectorScreen extends StatefulWidget {
  final VoidCallback onProfileSelected;
  
  const ProfileSelectorScreen({
    Key? key,
    required this.onProfileSelected,
  }) : super(key: key);
  
  @override
  State<ProfileSelectorScreen> createState() => _ProfileSelectorScreenState();
}

class _ProfileSelectorScreenState extends State<ProfileSelectorScreen> {
  final ProfileService _profileService = ProfileService();
  List<ChildProfile> _profiles = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }
  
  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    try {
      final profiles = await _profileService.loadProfiles();
      setState(() {
        _profiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.storage.e('Error loading profiles', error: e);
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _selectProfile(ChildProfile profile) async {
    await _profileService.setActiveProfile(profile.id);
    AppLogger.ui.i('Selected profile: ${profile.name}');
    widget.onProfileSelected();
  }
  
  Future<void> _selectGuest() async {
    await _profileService.setGuestMode();
    AppLogger.ui.i('Selected guest mode');
    widget.onProfileSelected();
  }
  
  Future<void> _addProfile() async {
    final newProfile = await showDialog<ChildProfile>(
      context: context,
      builder: (context) => const ProfileEditorDialog(),
    );
    
    if (newProfile != null) {
      await _profileService.addProfile(newProfile);
      await _loadProfiles();
    }
  }
  
  Future<void> _editProfile(ChildProfile profile) async {
    final editedProfile = await showDialog<ChildProfile>(
      context: context,
      builder: (context) => ProfileEditorDialog(profile: profile),
    );
    
    if (editedProfile != null) {
      await _profileService.updateProfile(editedProfile);
      await _loadProfiles();
    }
  }
  
  Future<void> _deleteProfile(ChildProfile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Are you sure you want to delete ${profile.name}\'s profile? All progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await _profileService.deleteProfile(profile.id);
      await _loadProfiles();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.school,
                          size: 64,
                          color: Colors.deepPurple.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Who\'s Learning Today?',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  // Profiles Grid
                  Expanded(
                    child: _profiles.isEmpty
                        ? _buildEmptyState()
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.9,
                            ),
                            itemCount: _profiles.length + 1, // +1 for guest
                            itemBuilder: (context, index) {
                              if (index == _profiles.length) {
                                return _buildGuestCard();
                              }
                              return _buildProfileCard(_profiles[index]);
                            },
                          ),
                  ),
                  
                  // Add Profile Button (for parents)
                  if (_profiles.length < 4) // Parent limit
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: OutlinedButton.icon(
                        onPressed: _addProfile,
                        icon: const Icon(Icons.add),
                        label: const Text('Add New Profile'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          side: BorderSide(color: Colors.deepPurple.shade300, width: 2),
                          foregroundColor: Colors.deepPurple.shade700,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
  
  Widget _buildProfileCard(ChildProfile profile) {
    return GestureDetector(
      onTap: () => _selectProfile(profile),
      onLongPress: () => _showProfileOptions(profile),
      child: Container(
        decoration: BoxDecoration(
          color: profile.color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Emoji avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  profile.emoji,
                  style: const TextStyle(fontSize: 48),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Name
            Text(
              profile.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            
            // Age
            if (profile.ageYears != null)
              Text(
                'Age ${profile.ageYears}',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGuestCard() {
    return GestureDetector(
      onTap: _selectGuest,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade400, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Guest icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline,
                size: 48,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            
            // Guest label
            Text(
              'Guest',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            
            Text(
              'Quick Play',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'No Profiles Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap "Add New Profile" below to create your first learner profile.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _addProfile,
              icon: const Icon(Icons.add),
              label: const Text('Add First Profile'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showProfileOptions(ChildProfile profile) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Profile'),
              onTap: () {
                Navigator.pop(context);
                _editProfile(profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Profile', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteProfile(profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

