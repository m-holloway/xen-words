<!-- e6c3d579-2546-4647-b97c-084c38721f0f 999e85d7-ab74-4c80-bc43-ceeadf19645a -->
# AI Art Generation Implementation Plan

## 1. File Organization & Prompt Relocation

Relocate prompt files from `to-be-relocated/` to a structured location:

- **New Location**: `lib/prompts/` directory
- **Files to Create**:
- `lib/prompts/panel_description_prompt.dart` - Contains the panel description generation prompt (from `to-be-relocated/prompt-create-panel-descriptions-from-story-text.xt`)
- `lib/prompts/panel_art_prompt.dart` - Contains the panel art grid generation prompt (from `to-be-relocated/prompt-create-panel-art-from-panel-descriptions.txt`)
- `lib/prompts/cover_art_prompt.dart` - **NEW**: Prompt for generating cover art from story + panel art (or story alone)
- `lib/prompts/character_extraction_prompt.dart` - **NEW**: Prompt to extract character descriptions for consistency

Each file exports a constant string that can be imported by services.

## 2. Core Infrastructure: `OpenRouterImageClient`

Create a dedicated service to handle image generation requests via OpenRouter.

- **Endpoint**: Use OpenRouter's `/api/v1/chat/completions` endpoint with `modalities: ["image", "text"]` (per [OpenRouter docs](https://openrouter.ai/docs/docs/overview/multimodal/image-generation))
- **Response Format**: Images returned as base64-encoded data URLs in `message.images[].image_url.url`
- **Aspect Ratio Support**: Use `image_config.aspect_ratio` parameter for Gemini models (e.g., `"3:4"` for book covers, `"1:1"` for panel grids)
- **Capabilities**:
- **Text-to-Image**: Generate images from prompts
- **Image + Text-to-Image**: Generate images with image input (for cover art using panel art)
- **Base64 Decoding**: Convert data URLs to local file storage
- **Models**: Support `google/gemini-2.5-flash-image` (cover) and `google/gemini-3-pro-image-preview` (panels)

## 3. Feature: Story Panel Art Generation (Primary Flow)

Implement the multi-step flow for generating consistent panel art. This is the **primary flow** that should be completed first.

### Step 1: Character Extraction (Text)

- **Action**: Send story text to LLM using `character_extraction_prompt.dart`
- **Output**: Structured list of character descriptions (name, gender, appearance, clothing, etc.)
- **Purpose**: Ensure character consistency across all panels

### Step 2: Panel Descriptions (Text)

- **Action**: Send full story text + character descriptions to LLM using `panel_description_prompt.dart`
- **Template Variables**: `[FULL_STORY_TEXT]`, `[CHARACTER_DESCRIPTIONS]`
- **Output**: A structured list of visual descriptions (one per paragraph)
- **Enhancement**: Prepend character descriptions to ensure consistency

### Step 3: Grid Generation (Image)

- **Action**: Send panel descriptions to Image Model using `panel_art_prompt.dart`
- **Model**: `google/gemini-3-pro-image-preview` (4x more expensive, better quality)
- **Resolution**: 1024x1024 (1:1 aspect ratio, model limit)
- **Template Variables**: 
- `[N]` - Number of panels
- `[PANEL_LIST]` - The panel descriptions
- Remove `[STYLE_REFERENCE_IMAGE_URL]` and replace with text-based style description
- **Style Description**: "Whimsical children's book illustration style, vibrant colors, soft lighting, age-appropriate for [child_age], warm and engaging"

### Step 4: Slicing & Assignment

- **Action**: Download the 1024x1024 grid image (base64 -> local file)
- **Processing**: Reuse `StoryPanelArtService._processPanelArt()` logic to slice the grid into N individual panel images
- **Assignment**: Automatically link sliced images to story paragraphs (1:1 mapping)
- **Storage**: Save via `StoryPanelArtService` methods

## 4. Feature: Book Cover Generation (Secondary Flow)

Generate cover art **after** panel art is available, using the panel art as visual reference.

### Flow A: Cover with Panel Art (Preferred)

- **Trigger**: "Generate AI Cover" button on story detail page (enabled if panel art exists)
- **Input**: 
- Story title, summary, full text
- Panel art image (1024x1024 grid) as visual reference
- Panel descriptions (for context)
- **Prompt**: Use `cover_art_prompt.dart` with image input
- **Model**: `google/gemini-2.5-flash-image` (cheaper, sufficient for covers)
- **Aspect Ratio**: `"3:4"` (864×1184) for book cover format
- **Process**: 

1. Send multimodal request with image + text prompt
2. Download generated cover (base64 -> local file)
3. Save via `StoryCoverService`

### Flow B: Cover without Panel Art (Fallback)

- **Trigger**: "Generate AI Cover" button (enabled even without panel art)
- **Input**: Story title, summary, full text only
- **Prompt**: Use `cover_art_prompt.dart` without image input (text-only variant)
- **Model**: `google/gemini-2.5-flash-image`
- **Aspect Ratio**: `"3:4"`
- **Note**: Prompt should explicitly state "children's book cover style" and include character descriptions if available

## 5. Prompt Engineering Details

### Panel Description Prompt (`lib/prompts/panel_description_prompt.dart`)

- Source: `to-be-relocated/prompt-create-panel-descriptions-from-story-text.xt`
- Enhancements:
- Add `[CHARACTER_DESCRIPTIONS]` section at top
- Emphasize: "Maintain character consistency using the provided character descriptions"

### Panel Art Prompt (`lib/prompts/panel_art_prompt.dart`)

- Source: `to-be-relocated/prompt-create-panel-art-from-panel-descriptions.txt`
- Changes:
- Remove `[STYLE_REFERENCE_IMAGE_URL]` section
- Replace with: `[ART_STYLE_DESCRIPTION]` (text-based, age-appropriate)
- Update resolution from 3200×3200 to 1024×1024
- Keep strict grid layout instructions

### Cover Art Prompt (`lib/prompts/cover_art_prompt.dart`) - **NEW**

Create a prompt that:

- **With Panel Art**: "Create a compelling children's book cover that captures the essence of this story. Use the provided panel art grid as visual reference for character design, color palette, and artistic style. The cover should be eye-catching and appropriate for [child_age]."
- **Without Panel Art**: "Create a compelling children's book cover for this story. Use a whimsical, age-appropriate illustration style with vibrant colors and engaging characters."
- Include story title, summary, and key themes
- Request 3:4 aspect ratio portrait orientation

## 6. User Interface Updates

- **StoryDetailScreen**: 
- Add "Generate Panel Art" button (primary action)
- Add "Generate Cover Art" button (secondary, enabled after panels or standalone)
- Show progress dialog with steps: "Extracting characters..." → "Writing panel descriptions..." → "Painting panels..." → "Slicing artwork..." → "Done!"
- **Art Progress Dialog**: 
- Multi-step progress indicator
- Cancel button (if possible)
- Preview of generated art before saving

## 7. Service Integration

- **Extend `StoryGeneratorService`**:
- `generatePanelArt(GeneratedStoryRecord story)` - Full panel art flow
- `generateCoverArt(GeneratedStoryRecord story, {String? panelArtImagePath})` - Cover generation with optional panel art
- **Create `OpenRouterImageClient`**:
- Handle image generation API calls
- Support multimodal requests (text + image input)
- Decode base64 images to local storage

## Implementation Order

1. Create `lib/prompts/` directory and relocate/refactor prompt files
2. Create `OpenRouterImageClient` service
3. Implement panel art generation flow (Steps 1-4)
4. Implement cover art generation flow (with and without panel art)
5. Update UI in `StoryDetailScreen`
6. Test end-to-end flow

### To-dos

- [ ] Create `lib/prompts/` directory and relocate prompt files from `to-be-relocated/`
- [ ] Create `lib/prompts/cover_art_prompt.dart` with prompts for cover generation (with/without panel art)
- [ ] Create `lib/prompts/character_extraction_prompt.dart` for character consistency
- [ ] Create `lib/services/openrouter_image_client.dart` to handle image generation API calls
- [ ] Update `StoryGeneratorService` with `generatePanelArt()` and `generateCoverArt()` methods
- [ ] Update `StoryDetailScreen` UI with generation buttons and progress dialogs