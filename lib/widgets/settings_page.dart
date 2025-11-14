import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_settings.dart';
import '../models/child_profile.dart';
import '../models/word_list.dart';
import '../screens/parent_dashboard_screen.dart';
import '../screens/profile_selector_screen.dart';
import '../services/preferences_service.dart';
import '../services/profile_service.dart';
import '../widgets/profile_editor_dialog.dart';

/// Settings page for parents with advanced configuration options
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
  final List<String> _dayNames = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];
  
  ChildProfile? _activeProfile;
  bool _isGuest = false;
  bool _profilesLoading = true;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _loadActiveProfile();
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
          'Settings',
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

          const SizedBox(height: 24),

          // Personalization Section
          _buildSection(
            title: 'Personalization',
            icon: Icons.person,
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Child\'s First Name',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This name will appear on the personalized rug in the learning space.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Enter name (e.g., Addy)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.badge),
                      ),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (value) {
                        _updateSettings(_settings.copyWith(childName: value));
                      },
                      controller: TextEditingController(text: _settings.childName)
                        ..selection = TextSelection.collapsed(
                          offset: _settings.childName.length,
                        ),
                    ),
                    if (_settings.hasChildName) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'The rug will show "${_settings.childName}"',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Font Selection Section
          _buildSection(
            title: 'Rug Font Style',
            icon: Icons.font_download,
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose a font for the welcome rug',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildFontPicker(),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Week Settings Section
          _buildSection(
            title: 'Week Settings',
            icon: Icons.calendar_today,
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Week',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Week ${_settings.currentWeek} of ${WordList.maxWeeks}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _settings.currentWeek.toDouble(),
                            min: 1,
                            max: WordList.maxWeeks.toDouble(),
                            divisions: WordList.maxWeeks - 1,
                            label: 'Week ${_settings.currentWeek}',
                            onChanged: (value) {
                              _updateSettings(
                                _settings.copyWith(currentWeek: value.toInt()),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 60,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_settings.currentWeek}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Auto-Advance Settings Section
          _buildSection(
            title: 'Auto-Advance Settings',
            icon: Icons.schedule,
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Automatically Advance Week',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Switch(
                          value: _settings.autoAdvanceEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings.copyWith(autoAdvanceEnabled: value),
                            );
                          },
                          activeColor: Colors.green,
                        ),
                      ],
                    ),
                    if (_settings.autoAdvanceEnabled) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Advance on:',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(7, (index) {
                          final isSelected = _settings.advanceDayOfWeek == index;
                          return ChoiceChip(
                            label: Text(_dayNames[index]),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                _updateSettings(
                                  _settings.copyWith(advanceDayOfWeek: index),
                                );
                              }
                            },
                            selectedColor: Colors.blue,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The week will automatically advance every ${_settings.getAdvanceDayName()}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Word List Settings Section
          _buildSection(
            title: 'Word List Settings',
            icon: Icons.book,
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Words Per Week',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Currently: ${_settings.wordsPerWeek} words per week',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Note: Changing this setting will affect which words are available. This feature may be expanded in future updates.',
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

          const SizedBox(height: 24),

          // Info Section
          _buildSection(
            title: 'Information',
            icon: Icons.info,
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Total Weeks', '${WordList.maxWeeks}'),
                    const Divider(),
                    _buildInfoRow('Total Words', '${WordList.allWords.length}'),
                    const Divider(),
                    _buildInfoRow(
                      'Words in Current Week',
                      '${_settings.currentWeek * _settings.wordsPerWeek}',
                    ),
                    const Divider(),
                    _buildInfoRow(
                      'Words Available',
                      '${_settings.currentWeek * _settings.wordsPerWeek} (weeks 1-${_settings.currentWeek})',
                    ),
                  ],
                ),
              ),
            ],
          ),

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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontPicker() {
    final fonts = [
      {'name': 'Quicksand', 'description': 'Playful & Rounded'},
      {'name': 'Nunito', 'description': 'Clean & Friendly'},
      {'name': 'Fredoka', 'description': 'Super Playful'},
      {'name': 'Chewy', 'description': 'Fun & Chunky'},
      {'name': 'Rubik Bubbles', 'description': 'Bubbly Fun'},
      {'name': 'Righteous', 'description': 'Bold & Modern'},
      {'name': 'Galindo', 'description': 'Quirky & Fun'},
      {'name': 'Pacifico', 'description': 'Casual Script'},
      {'name': 'Lavishly Yours', 'description': 'Elegant Script'},
      {'name': 'Ballet', 'description': 'Graceful Script'},
    ];

    return Column(
      children: fonts.map((font) {
        final fontName = font['name']!;
        final isSelected = _settings.rugFontFamily == fontName;
        
        return GestureDetector(
          onTap: () {
            _updateSettings(_settings.copyWith(rugFontFamily: fontName));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? Colors.purple.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.purple : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Radio button
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? Colors.purple : Colors.grey,
                ),
                const SizedBox(width: 16),
                // Font preview and info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Font name and description
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            fontName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            font['description']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Preview text
                      Text(
                        _settings.hasChildName 
                            ? 'Welcome ${_settings.childName}!'
                            : 'Welcome Adalyn!',
                        style: _getFontStyle(fontName).copyWith(
                          fontSize: 24,
                          color: const Color(0xFF3C2814),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  TextStyle _getFontStyle(String fontName) {
    switch (fontName) {
      case 'Quicksand':
        return GoogleFonts.quicksand(fontWeight: FontWeight.w700);
      case 'Nunito':
        return GoogleFonts.nunito(fontWeight: FontWeight.w700);
      case 'Fredoka':
        return GoogleFonts.fredoka(fontWeight: FontWeight.w700);
      case 'Chewy':
        return GoogleFonts.chewy();
      case 'Rubik Bubbles':
        return GoogleFonts.rubikBubbles();
      case 'Righteous':
        return GoogleFonts.righteous();
      case 'Galindo':
        return GoogleFonts.galindo();
      case 'Pacifico':
        return GoogleFonts.pacifico();
      case 'Lavishly Yours':
        return GoogleFonts.lavishlyYours();
      case 'Ballet':
        return GoogleFonts.ballet();
      default:
        return GoogleFonts.quicksand(fontWeight: FontWeight.w700);
    }
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
}

