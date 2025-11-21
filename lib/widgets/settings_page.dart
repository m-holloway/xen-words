import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/child_profile.dart';
import '../models/story_generation_models.dart';
import '../screens/learning_plan_screen.dart';
import '../screens/parent_dashboard_screen.dart';
import '../screens/profile_selector_screen.dart';
import '../screens/story_generator_screen.dart';
import '../services/preferences_service.dart';
import '../services/profile_service.dart';
import '../services/story_generator_service.dart';
import '../utils/app_logger.dart';
import '../widgets/profile_editor_dialog.dart';

/// Parent dashboard hub for adults to manage settings, learning tools, and data
class SettingsPage extends StatefulWidget {
  final AppSettings initialSettings;
  final Function(AppSettings) onSettingsChanged;

  const SettingsPage({
    Key? key,
    required this.initialSettings,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _settings;
  ChildProfile? _activeProfile;
  bool _isGuest = false;
  bool _profilesLoading = true;
  final StoryGeneratorService _storyService = StoryGeneratorService();
  GeneratedStoryRecord? _latestStory;
  int _personalStoryCount = 0;
  int _builtInStoryCount = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _loadActiveProfile();
    _refreshStoryLabPeek();
  }
  
  Future<void> _loadActiveProfile() async {
    setState(() => _profilesLoading = true);
    try {
      final profileService = ProfileService();
      final isGuest = await profileService.isGuestMode();
      
      if (isGuest) {
        setState(() {
          _isGuest = true;
          _activeProfile = null;
          _profilesLoading = false;
        });
      } else {
        final activeProfileId = await profileService.getActiveProfileId();
        if (activeProfileId != null) {
          final profiles = await profileService.loadProfiles();
          final profile = profiles.where((p) => p.id == activeProfileId).firstOrNull;
          setState(() {
            _activeProfile = profile;
            _isGuest = false;
            _profilesLoading = false;
          });
        } else {
          setState(() => _profilesLoading = false);
        }
      }
    } catch (e) {
      setState(() => _profilesLoading = false);
    }
  }
  
  Future<void> _switchProfile() async {
    // Navigate to profile selector
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileSelectorScreen(
          onProfileSelected: () {
            Navigator.of(context).pop(true);
          },
        ),
      ),
    );
    
    // If profile was selected, pop back to home screen to reload
    if (result == true && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
  
  Future<void> _editActiveProfile() async {
    if (_activeProfile == null) return;
    
    final editedProfile = await showDialog<ChildProfile>(
      context: context,
      builder: (context) => ProfileEditorDialog(profile: _activeProfile),
    );
    
    if (editedProfile != null) {
      await ProfileService().updateProfile(editedProfile);
      _loadActiveProfile();
    }
  }

  Future<void> _refreshStoryLabPeek() async {
    try {
      final stories = await _storyService.loadStories();
      if (!mounted) return;
      setState(() {
        _personalStoryCount = stories.where((story) => !story.isBuiltIn).length;
        _builtInStoryCount = stories.where((story) => story.isBuiltIn).length;
        _latestStory = stories.isNotEmpty ? stories.first : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _personalStoryCount = 0;
          _builtInStoryCount = 0;
          _latestStory = null;
        });
      }
    }
  }

  Future<void> _openStoryLab({StoryLabView view = StoryLabView.library}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryGeneratorScreen(initialView: view),
      ),
    );
    await _refreshStoryLabPeek();
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Parent Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active Profile Card
          if (!_profilesLoading)
            _buildSection(
              title: 'Active Profile',
              icon: Icons.person,
              children: [
                _buildCard(
                  child: _isGuest
                      ? _buildGuestProfileCard()
                      : _activeProfile != null
                          ? _buildActiveProfileCard(_activeProfile!)
                          : _buildNoProfileCard(),
                ),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Progress Dashboard Link
          _buildCard(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dashboard, color: Colors.deepPurple, size: 28),
              ),
              title: const Text(
                'Progress Dashboard',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('View your child\'s learning progress and stats'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ParentDashboardScreen(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          _buildNavigationCard(
            icon: Icons.school,
            iconColor: Colors.teal,
            title: 'Learning Plan',
            subtitle: 'Week ${_settings.currentWeek} | ${_settings.wordsPerWeek} words/week',
            onTap: _openLearningPlan,
          ),

          const SizedBox(height: 24),

          _buildStoryLabCard(),

          const SizedBox(height: 24),
          _buildDataManagementSection(),

          // Developer Section (Debug mode only)
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            _buildSection(
              title: '🔧 Developer Tools',
              icon: Icons.code,
              children: [
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Development Mode Only - Not visible in production',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // Show confirmation dialog
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Reset Onboarding'),
                              content: const Text(
                                'This will reset the onboarding flag and show the welcome flow again on next app restart.\n\nContinue?'
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                  ),
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await PreferencesService().setOnboardingComplete(false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Onboarding reset! Restart the app to see the welcome flow.'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.replay),
                        label: const Text('Reset Onboarding'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Use this to test the onboarding flow without clearing all app data.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.blue, size: 24),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _buildActiveProfileCard(ChildProfile profile) {
    return Column(
      children: [
        Row(
          children: [
            // Avatar
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: profile.color,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  profile.emoji,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Name and age
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (profile.ageYears != null)
                    Text(
                      'Age ${profile.ageYears}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            
            // Actions
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editActiveProfile,
              tooltip: 'Edit Profile',
            ),
          ],
        ),
        const Divider(height: 24),
        ElevatedButton.icon(
          onPressed: _switchProfile,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Switch Profile'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
  
  Widget _buildGuestProfileCard() {
    return Column(
      children: [
        Row(
          children: [
            // Guest icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline,
                size: 32,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 16),
            
            // Guest label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Guest',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Quick play mode - progress not saved',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        ElevatedButton.icon(
          onPressed: _switchProfile,
          icon: const Icon(Icons.person_add),
          label: const Text('Create or Select Profile'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
  
  Widget _buildNoProfileCard() {
    return Column(
      children: [
        Icon(
          Icons.person_off,
          size: 48,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 16),
        const Text(
          'No Active Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select or create a profile to track progress',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _switchProfile,
          icon: const Icon(Icons.person_add),
          label: const Text('Select Profile'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Future<void> _openLearningPlan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LearningPlanScreen(
          initialSettings: _settings,
          onSettingsChanged: _updateSettings,
        ),
      ),
    );
  }

  Widget _buildNavigationCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _buildCard(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 28),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildStoryLabCard() {
    final personalLabel = _personalStoryCount > 0
        ? '$_personalStoryCount personal · $_builtInStoryCount built-in'
        : '$_builtInStoryCount built-in bedtime stories ready';
    final latestTitle = _latestStory?.chapter.title;

    const Color gradientStart = Color(0xFF3730A3);
    const Color gradientEnd = Color(0xFF7C3AED);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF3730A3),
            Color(0xFF7C3AED),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientStart.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _openStoryLab,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.smart_toy,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Story Time',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            personalLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _personalStoryCount > 0
                      ? 'Custom stories tuned for your child, plus read-only built-in adventures.'
                      : 'Built-in calming stories plus AI-generated tales you can create in minutes.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    height: 1.3,
                  ),
                ),
                if (latestTitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Latest: $latestTitle',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _StoryLabTag('Reading-level aware'),
                    _StoryLabTag('Parent + child prompts'),
                    _StoryLabTag('Saved for rereads'),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: gradientStart,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _openStoryLab,
                        child: const Text('Open library'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: gradientEnd.withOpacity(0.55)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _openStoryLab(view: StoryLabView.generator),
                        child: const Text('New story'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataManagementSection() {
    return _buildSection(
      title: 'Privacy & Data',
      icon: Icons.shield,
      children: [
        _buildCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blue),
                title: const Text('Data Storage'),
                subtitle: const Text('All progress stays on this device'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDataInfoDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete All Data'),
                subtitle: const Text('Removes settings, profiles, and progress'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _confirmDeleteAllData,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDataInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Your Data'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'What data is stored:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Words attempted and mastered'),
              Text('• Session history and dates'),
              Text('• Success rates and progress'),
              Text('• Child\'s name (for personalization)'),
              Text('• Week progression'),
              SizedBox(height: 16),
              Text(
                'Privacy guarantees:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('✓ Stored only on this device'),
              Text('✓ Never transmitted over internet'),
              Text('✓ Not shared with anyone'),
              Text('✓ Deleted when app is uninstalled'),
              SizedBox(height: 16),
              Text(
                'No audio recordings are ever saved.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAllData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Data?'),
        content: const Text(
          'This will permanently delete all progress, session history, and settings. This cannot be undone.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await PreferencesService().clearAllData();
                if (!mounted) return;
                Navigator.pop(context); // dialog
                Navigator.pop(context); // dashboard
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All data deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                AppLogger.system.e('Failed to delete data', error: e);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting data: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}

class _StoryLabTag extends StatelessWidget {
  const _StoryLabTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

