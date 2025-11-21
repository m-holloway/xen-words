import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_settings.dart';

/// Dedicated screen for managing personalization settings like the rug name
/// and font. This keeps the main settings surface focused on navigation.
class PersonalizationScreen extends StatefulWidget {
  final AppSettings initialSettings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const PersonalizationScreen({
    super.key,
    required this.initialSettings,
    required this.onSettingsChanged,
  });

  @override
  State<PersonalizationScreen> createState() => _PersonalizationScreenState();
}

class _PersonalizationScreenState extends State<PersonalizationScreen> {
  late AppSettings _settings;
  late final TextEditingController _nameController;

  final List<Map<String, String>> _fonts = const [
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

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _nameController = TextEditingController(text: widget.initialSettings.childName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
      if (_nameController.text != newSettings.childName) {
        _nameController.value = TextEditingValue(
          text: newSettings.childName,
          selection: TextSelection.collapsed(offset: newSettings.childName.length),
        );
      }
    });
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Personalization',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make the learning space feel special by adding your child\'s name '
                  'and choosing a welcome rug font.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSection(
            title: 'Child\'s First Name',
            icon: Icons.badge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter name (e.g., Addy)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (value) {
                    _updateSettings(_settings.copyWith(childName: value));
                  },
                ),
                if (_settings.hasChildName) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The rug will show "${_settings.childName}".',
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
          const SizedBox(height: 24),
          _buildSection(
            title: 'Rug Font Style',
            icon: Icons.font_download,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview how the welcome rug greets your child.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                ..._fonts.map(_buildFontOption),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFontOption(Map<String, String> font) {
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
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? Colors.purple : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
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
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildCard(child: child),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
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
}


