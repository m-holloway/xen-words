class ModelOption {
  final String id;
  final String label;
  final String? note;

  const ModelOption({
    required this.id,
    required this.label,
    this.note,
  });
}

/// Central place to configure available LLM and image models for Story Time.
class ModelConfig {
  // Core story text models (used for full story generation)
  static const List<ModelOption> storyModels = [
    ModelOption(
      id: 'moonshotai/kimi-k2-thinking',
      label: 'Kimi K2 (thinking)',
      note: 'High-quality long-form reasoning; current primary.',
    ),
    ModelOption(
      id: 'qwen/qwen3-vl-30b-a3b-instruct',
      label: 'Qwen3 VL 30B',
      note: 'Vision-language model; good for multimodal experiments.',
    ),
    ModelOption(
      id: 'qwen/qwen3-vl-235b-a22b-instruct',
      label: 'Qwen3 VL 235B',
      note: 'Vision-language model; good for multimodal experiments.',
    ),
    ModelOption(
      id: 'google/gemini-3-pro-preview',
      label: 'Gemini 3 Pro (preview)',
    ),
    ModelOption(
      id: 'google/gemini-2.5-flash-preview-09-2025',
      label: 'Gemini 2.5 Flash (09‑2025)',
    ),
    //moonshotai/kimi-k2-0905
    ModelOption(
      id: 'moonshotai/kimi-k2-0905',
      label: 'Kimi K2 (09‑05)',
    ),
  ];

  // Image models (for any illustration task)
  static const List<ModelOption> imageModels = [
    ModelOption(
      id: 'google/gemini-2.5-flash-image',
      label: 'Gemini 2.5 Flash Image',
    ),
    ModelOption(
      id: 'openai/gpt-5-image-mini',
      label: 'GPT-5 Image Mini',
    ),
    ModelOption(
      id: 'google/gemini-3-pro-image-preview',
      label: 'Gemini 3 Pro Image (preview)',
    ),
    ModelOption(
      id: 'openai/gpt-5-image',
      label: 'GPT-5 Image',
    ),
  ];

  /// Default model IDs by role. These can all be pointed at the same
  /// underlying model string or varied independently as needed.

  /// Primary story text model (full story generation).
  static const String defaultStoryModelId = 'moonshotai/kimi-k2-thinking';

  /// LLM used for **character extraction** from story text.
  static const String defaultCharacterExtractionModelId =
      'moonshotai/kimi-k2-0905';

  /// LLM used for **panel description** generation from story text.
  static const String defaultPanelDescriptionModelId =
      'moonshotai/kimi-k2-0905';

  /// Image model for **book cover art**.
  static const String defaultCoverModelId = 'google/gemini-2.5-flash-image';

  /// Image model for **panel art grids**.
  static const String defaultPanelModelId = 'google/gemini-2.5-flash-image';

  /// Image model for **Story World portraits / character art**.
  static const String defaultPortraitModelId = defaultCoverModelId;
}


