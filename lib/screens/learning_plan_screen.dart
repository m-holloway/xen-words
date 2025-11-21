import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/word_list.dart';

/// Screen that groups all week pacing, auto-advance, and informational cards.
class LearningPlanScreen extends StatefulWidget {
  final AppSettings initialSettings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const LearningPlanScreen({
    super.key,
    required this.initialSettings,
    required this.onSettingsChanged,
  });

  @override
  State<LearningPlanScreen> createState() => _LearningPlanScreenState();
}

class _LearningPlanScreenState extends State<LearningPlanScreen> {
  late AppSettings _settings;

  final List<String> _dayNames = const [
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
      appBar: AppBar(
        title: const Text(
          'Learning Plan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: 'Week Settings',
            icon: Icons.calendar_today,
            child: _buildWeekCard(),
          ),
          const SizedBox(height: 24),
          _buildSection(
            title: 'Auto-Advance',
            icon: Icons.schedule,
            child: _buildAutoAdvanceCard(),
          ),
          const SizedBox(height: 24),
          _buildSection(
            title: 'Word List Settings',
            icon: Icons.book,
            child: _buildWordListCard(),
          ),
          const SizedBox(height: 24),
          _buildSection(
            title: 'Information',
            icon: Icons.info,
            child: _buildInformationCard(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildWeekCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Week',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildAutoAdvanceCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Automatically advance to the next week',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Switch(
              value: _settings.autoAdvanceEnabled,
              onChanged: (value) {
                _updateSettings(_settings.copyWith(autoAdvanceEnabled: value));
              },
              activeColor: Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Keep practice fresh by moving to a new set of words on a schedule.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        if (_settings.autoAdvanceEnabled) ...[
          const SizedBox(height: 20),
          const Text(
            'Advance on',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
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
                    _updateSettings(_settings.copyWith(advanceDayOfWeek: index));
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
          const SizedBox(height: 12),
          Text(
            'The week will automatically advance every ${_settings.getAdvanceDayName()}.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWordListCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Words per Week',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Currently: ${_settings.wordsPerWeek} words per week',
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'These advanced controls are in-progress. Changing this value now will alter which words are available in each week.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildInformationCard() {
    return Column(
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
          '${_settings.currentWeek * _settings.wordsPerWeek} '
          '(weeks 1-${_settings.currentWeek})',
        ),
      ],
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}


