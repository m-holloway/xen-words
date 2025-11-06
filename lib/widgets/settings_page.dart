import 'package:flutter/material.dart';
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
}

