import 'package:flutter/material.dart';

import '../models/story_generation_models.dart';
import '../services/story_generator_service.dart';
import '../utils/story_text_utils.dart';

class StoryRevisionScreen extends StatefulWidget {
  const StoryRevisionScreen({
    super.key,
    required this.story,
    required this.storyService,
  });

  final GeneratedStoryRecord story;
  final StoryGeneratorService storyService;

  @override
  State<StoryRevisionScreen> createState() => _StoryRevisionScreenState();
}

class _StoryRevisionScreenState extends State<StoryRevisionScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _instructionsController = TextEditingController();

  StoryRevisionDraft? _draft;
  bool _isSubmitting = false;
  bool _isApproving = false;
  String? _error;

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _draft;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revise Story'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What would you like to revise about "${widget.story.chapter.title}"?',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _instructionsController,
                    minLines: 4,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Revision details',
                      hintText: 'Focus on the specific part you want to adjust',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please describe the revision you have in mind.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : _requestRevision,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_fix_high),
                        label: Text(_isSubmitting ? 'Generating...' : 'Generate Revision'),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                if (draft != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Proposed revision',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft.record.chapter.title,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            draft.record.summary,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 220,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                StoryTextUtils.narrationOnly(draft.record.chapter),
                                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Model: ${draft.modelId}',
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isApproving ? null : _approveRevision,
                      icon: _isApproving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isApproving ? 'Saving...' : 'Approve Revision'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestRevision() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
      _draft = null;
    });
    try {
      final draft = await widget.storyService.draftRevision(
        widget.story,
        _instructionsController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _approveRevision() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _isApproving = true;
      _error = null;
    });
    try {
      final updated = await widget.storyService.applyRevision(
        storyId: widget.story.id,
        draft: draft,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isApproving = false;
      });
    }
  }
}

