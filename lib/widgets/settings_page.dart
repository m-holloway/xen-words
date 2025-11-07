import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_settings.dart';
import '../models/word_list.dart';

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

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
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
          // Personalization Section
          _buildSection(
            title: 'Personalization',
            icon: Icons.person,
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Child\'s First Name',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This name will appear on the personalized rug in the learning space.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
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
}

