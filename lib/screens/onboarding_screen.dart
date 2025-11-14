import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../services/profile_service.dart';
import '../models/child_profile.dart';
import '../utils/app_logger.dart';

/// Onboarding flow for first-time users
/// Explains offline nature, requests microphone permission, collects child name
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const OnboardingScreen({
    Key? key,
    required this.onComplete,
  }) : super(key: key);
  
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  int _currentPage = 0;
  
  // Profile customization
  String _selectedEmoji = '😊';
  Color _selectedColor = Colors.purple.shade300;
  int _selectedAge = 5;
  
  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }
  
  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }
  
  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  Future<void> _completeOnboarding() async {
    try {
      final prefs = PreferencesService();
      final profileService = ProfileService();
      
      // Create first profile if name is provided
      if (_nameController.text.isNotEmpty) {
        final name = _nameController.text.trim();
        
        // Save to legacy settings for backward compatibility
        final settings = await prefs.loadSettings();
        await prefs.saveSettings(
          settings.copyWith(childName: name),
        );
        
        // Create first child profile with user selections
        final now = DateTime.now();
        final firstProfile = ChildProfile(
          id: ProfileService.generateId(),
          name: name,
          ageYears: _selectedAge,
          emoji: _selectedEmoji,
          color: _selectedColor,
          createdDate: now,
          lastActiveDate: now,
        );
        
        await profileService.addProfile(firstProfile);
        await profileService.setActiveProfile(firstProfile.id);
        
        AppLogger.ui.i('Created first profile: $name');
      }
      
      // Mark onboarding as complete
      await prefs.setOnboardingComplete(true);
      
      AppLogger.ui.i('Onboarding completed successfully');
      
      // Call onComplete after all saves are done
      widget.onComplete();
    } catch (e) {
      AppLogger.storage.e('Error completing onboarding', error: e);
      // Still complete onboarding even if save failed
      widget.onComplete();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildWelcomePage(),
                  _buildPrivacyPage(),
                  _buildPersonalizationPage(),
                  _buildCustomizationPage(),
                ],
              ),
            ),
            _buildNavigationBar(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.waving_hand,
            size: 100,
            color: Colors.amber[600],
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to Xen Words!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Help your child learn sight words through the power of their own voice!',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          _buildFeatureItem(
            icon: Icons.mic,
            title: 'Speech Recognition',
            description: 'Your child speaks, we listen and respond',
          ),
          const SizedBox(height: 16),
          _buildFeatureItem(
            icon: Icons.pets,
            title: 'Animated Character',
            description: 'Friendly 3D rabbit companion celebrates success',
          ),
          const SizedBox(height: 16),
          _buildFeatureItem(
            icon: Icons.school,
            title: '61 Sight Words',
            description: 'Organized across 31 weeks of learning',
          ),
        ],
      ),
    );
  }
  
  Widget _buildPrivacyPage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 100,
            color: Colors.green[600],
          ),
          const SizedBox(height: 32),
          Text(
            'Privacy You Can Trust',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Your child\'s privacy is our highest priority.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          _buildPrivacyItem(
            icon: Icons.wifi_off,
            title: '100% Offline',
            description: 'No internet connection needed or used',
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          _buildPrivacyItem(
            icon: Icons.mic_off,
            title: 'No Recordings',
            description: 'Voice is processed instantly and never saved',
            color: Colors.purple,
          ),
          const SizedBox(height: 16),
          _buildPrivacyItem(
            icon: Icons.shield_outlined,
            title: 'Zero Tracking',
            description: 'No data collection, ads, or monitoring',
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          _buildPrivacyItem(
            icon: Icons.phone_android,
            title: 'Local Only',
            description: 'All data stays on your device',
            color: Colors.orange,
          ),
        ],
      ),
    );
  }
  
  Widget _buildPersonalizationPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.child_care,
            size: 80,
            color: Colors.pink[400],
          ),
          const SizedBox(height: 24),
          Text(
            'Child\'s Name',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Enter your child\'s first name to personalize their learning space.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Child\'s First Name',
              hintText: 'Alex',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.person),
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'We\'ll ask for microphone permission when you start your first lesson.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCustomizationPage() {
    final name = _nameController.text.trim();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Preview card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _selectedColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _selectedEmoji,
                      style: const TextStyle(fontSize: 40),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Preview' : name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Age $_selectedAge',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Age selector
          Text(
            'Age',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: List.generate(8, (index) {
              final age = index + 3; // Ages 3-10
              final isSelected = _selectedAge == age;
              return ChoiceChip(
                label: Text('$age'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedAge = age);
                },
                selectedColor: Colors.deepPurple,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              );
            }),
          ),
          
          const SizedBox(height: 24),
          
          // Emoji selector
          Text(
            'Avatar',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: ['😊', '🌟', '🎈', '🦄', '🐶', '🐱', '🦊', '🐻', '🐼', '🦁', '🐯', '🐸'].map((emoji) {
              final isSelected = _selectedEmoji == emoji;
              return GestureDetector(
                onTap: () => setState(() => _selectedEmoji = emoji),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.deepPurple.shade50 : Colors.grey.shade100,
                    border: Border.all(
                      color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
                      width: isSelected ? 3 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 24),
          
          // Color selector
          Text(
            'Color',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              Colors.pink.shade300,
              Colors.purple.shade300,
              Colors.blue.shade300,
              Colors.green.shade300,
              Colors.orange.shade300,
              Colors.red.shade300,
              Colors.teal.shade300,
              Colors.amber.shade300,
            ].map((color) {
              final isSelected = _selectedColor == color;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.black87 : Colors.grey.shade300,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 32)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.deepPurple, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildPrivacyItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
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
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.check_circle, color: color, size: 20),
      ],
    );
  }
  
  Widget _buildNavigationBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              4,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? Colors.deepPurple
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Navigation buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_currentPage > 0)
                TextButton(
                  onPressed: _previousPage,
                  child: const Text('Back'),
                )
              else
                const SizedBox(width: 80),
              
              if (_currentPage < 3)
                ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Next'),
                )
              else
                ElevatedButton(
                  onPressed: _completeOnboarding,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Get Started!'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

