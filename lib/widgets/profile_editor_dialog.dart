import 'package:flutter/material.dart';
import '../models/child_profile.dart';
import '../services/profile_service.dart';

/// Dialog for creating or editing a child profile
class ProfileEditorDialog extends StatefulWidget {
  final ChildProfile? profile; // Null for new profile
  
  const ProfileEditorDialog({
    Key? key,
    this.profile,
  }) : super(key: key);
  
  @override
  State<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<ProfileEditorDialog> {
  late TextEditingController _nameController;
  late int _selectedAge;
  late String _selectedEmoji;
  late Color _selectedColor;
  
  final List<String> _emojiOptions = [
    '😊', '🌟', '🎈', '🦄', '🐶', '🐱', '🦊', '🐻',
    '🐼', '🦁', '🐯', '🐸', '🦋', '🌈', '🎨', '🎭',
  ];
  
  final List<Color> _colorOptions = [
    Colors.pink.shade300,
    Colors.purple.shade300,
    Colors.blue.shade300,
    Colors.green.shade300,
    Colors.orange.shade300,
    Colors.red.shade300,
    Colors.teal.shade300,
    Colors.amber.shade300,
  ];
  
  @override
  void initState() {
    super.initState();
    
    // Initialize with existing profile or defaults
    _nameController = TextEditingController(
      text: widget.profile?.name ?? '',
    );
    _selectedAge = widget.profile?.ageYears ?? 5;
    _selectedEmoji = widget.profile?.emoji ?? _emojiOptions[0];
    _selectedColor = widget.profile?.color ?? _colorOptions[0];
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
  
  void _save() {
    final name = _nameController.text.trim();
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }
    
    final now = DateTime.now();
    final profile = ChildProfile(
      id: widget.profile?.id ?? ProfileService.generateId(),
      name: name,
      ageYears: _selectedAge,
      emoji: _selectedEmoji,
      color: _selectedColor,
      createdDate: widget.profile?.createdDate ?? now,
      lastActiveDate: now,
    );
    
    Navigator.pop(context, profile);
  }
  
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.profile != null;
    
    return AlertDialog(
      title: Text(isEditing ? 'Edit Profile' : 'New Profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview card
            _buildPreviewCard(),
            
            const SizedBox(height: 24),
            
            // Name input
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Child\'s Name',
                hintText: 'Alex',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: !isEditing,
              onChanged: (_) => setState(() {}),
            ),
            
            const SizedBox(height: 20),
            
            // Age selector
            const Text(
              'Age',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                  ),
                );
              }),
            ),
            
            const SizedBox(height: 20),
            
            // Emoji selector
            const Text(
              'Avatar',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _emojiOptions.map((emoji) {
                final isSelected = _selectedEmoji == emoji;
                return GestureDetector(
                  onTap: () => setState(() => _selectedEmoji = emoji),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.deepPurple.shade50 : Colors.grey.shade100,
                      border: Border.all(
                        color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
                        width: isSelected ? 3 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 20),
            
            // Color selector
            const Text(
              'Color',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _colorOptions.map((color) {
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black87 : Colors.grey.shade300,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 28)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
  
  Widget _buildPreviewCard() {
    final name = _nameController.text.trim();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _selectedColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _selectedEmoji,
                style: const TextStyle(fontSize: 36),
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
                  name.isEmpty ? 'Preview' : name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Age $_selectedAge',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

