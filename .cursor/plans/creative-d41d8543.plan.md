<!-- d41d8543-911e-44cc-9f91-c11784b91fea 2f347634-0c1a-4595-b2ea-a67bd10ba163 -->
# Creative Story Companion Feature Plan (Revised with Caching, Preference Conditioning, and Two-Stage Scoring)

## 1. Clarify Goals, Constraints, and Success Criteria

- Define target age ranges, reading levels, and primary use cases (solo child, child + parent, siblings).
- Decide supported platforms for this feature (iOS, Android, tablet form factors) and performance constraints (latency targets for suggestions, offline behavior if no network).
- Choose LLM backend(s) and cost guardrails using the existing OpenRouter strategy (max tokens per story, rate limits, caching strategy, fallback behavior when API fails).
- Establish measurable success metrics (time-on-task, number of stories completed, suggestions accepted vs. user-created sentences, parental satisfaction feedback, and average token cost per story).

## 2. Story Model, Data Structures, and Persistence

- **Story entity**: Define a `StorySession` model with fields like `id`, `title`, `createdAt`, `updatedAt`, `participants`, `currentIndex`, `sentences`, and metadata (age range, theme, difficulty, safety flags, cost metrics).
- **Sentence node model**: Represent each story step as a `SentenceNode` with:
- The accepted sentence text.
- Speaker (child, parent, AI, mixed).
- Timestamps and audio references (recordings, TTS audio).
- A list of `AlternativeSuggestion` objects: the two surfaced AI candidates plus any hidden candidates used for analytics.
- A small `InteractionMeta` structure storing: which alternative set was offered, which option (A/B/Write-in) was chosen, and optional tags like "preferred sillier option" or "preferred calmer option".
- **Branching & revisions**: Support a simple branching model:
- When a user edits/deletes a past sentence and continues, create a new branch or mark subsequent nodes as invalidated and regenerate suggestions based on the new context.
- Store which branch is currently “active” for playback and editing.
- **Preference trace**: Maintain a lightweight per-story `PreferenceTrace` summarizing user choices (e.g., counts of A vs. B vs. write-in, tags for tone preferences). This can be fed into prompts for later steps.
- **Persistence layer**: Decide how and where to store stories:
- On-device local DB (e.g., SQLite/hive) for fast access and privacy.
- Optional cloud sync for backing up stories across devices and for parents.
- **Serialization and migration**: Define JSON schema for story export/import and future schema evolution.

## 3. LLM Prompting, Caching, and Two-Stage Suggestion Pipeline

- **Reuse existing story backend patterns**:
- Build on the existing story-generation backend and OpenRouter integration (e.g., as in [`genai/story_generator`](genai/story_generator)), sharing auth, client abstractions, logging, and error handling.
- Add a dedicated “creative sentence game” prompt profile that is tuned independently from other story-generation modes.
- **Primary generator model (Stage 1)**:
- Use a strong creative model as the **generator**. System prompt instructs it to:
  - Return exactly 5 single-sentence candidates, no explanations.
  - For each candidate, provide self-scores along clearly defined axes: creativity, coherence, surprise, emotional warmth, linguistic simplicity, and safety adherence.
  - Emit a strict JSON schema for easy parsing (`[{id, text, scores: {...}}]`).
- Encode the “creative sentence game” behavior: prioritize delight, surprise, humor, and open loops while staying age-appropriate and maintaining continuity.
- **Incremental, cache-aware prompting for the generator**:
- Structure prompts with a **stable preamble** (rules, safety, style) that never changes and is ideal for provider-level caching.
- Maintain a **cached story context block** comprising either:
  - A rolling summary of the story so far **plus** the last N accepted sentences, or
  - A compact log for the last K steps: `Step n: options [A,B,...], child chose [A/B/Write-in: "..."]`.
- On each new turn, reuse this cached preamble and context and only append:
  - The newest accepted sentence.
  - A short note about the latest choice (e.g., "The child preferred the sillier option B" or "The child wrote their own gentle line").
- Design this cached prefix to be deterministic so upstream prompt caching (via OpenRouter/model) can kick in.
- **Preference-aware context**:
- For the last K turns (e.g., 5–8), include user choice metadata: A/B/write-in, a short label for why it may have been preferred (derived from scores), and brief notes about rejected options only when informative.
- Keep earlier turns summarized into a compact `PreferenceTrace` (e.g., "often prefers silly animal twists, avoids spooky scenes").
- **Secondary ranker model (Stage 2)**:
- Use a smaller, faster, cheaper model as a **ranker/discriminator**.
- Input: the 5 candidates from Stage 1 with their self-scores, plus a compact context (rolling story summary, last few sentences, and recent `PreferenceTrace`).
- Task: re-score and re-rank the candidates focusing on:
  - Consistency with characters, setting, and ongoing themes.
  - Alignment with the child’s observed preferences.
  - App-specific objectives (e.g., gently encouraging the child’s own ideas if they’ve relied heavily on AI options).
- Output: final scores per candidate and an ordering; keep a strict JSON schema (`[{id, rerank_score, reasons}]`).
- **Combined scoring & selection policy**:
- Combine Stage 1 self-scores and Stage 2 rerank scores into a deterministic selection function (e.g., weighted sum with safety as a hard gate and diversity as a soft penalty).
- Select the top 2 candidates as the visible suggestions; keep all 5 with both score sets in metadata for analytics and future tuning.
- **Safety & content filters**:
- Bake safety constraints into both model prompts (generator and ranker) and, if needed, run a final lightweight classifier.
- If any candidate is flagged unsafe, drop it and optionally re-query; if too many are removed, bias toward encouraging user-authored sentences.

## 4. Backend / Service Design for Story Suggestions, Caching, and Cost Control

- **Story suggestion service**:
- Implement a `StorySuggestionService` on the backend that orchestrates:
  - Constructing cached prompts for the generator.
  - Calling the Stage 1 generator model via OpenRouter.
  - Invoking the Stage 2 ranker with generator outputs and compact context.
  - Applying safety, selection policy, and caching of final results when possible.
- **API contract**:
- Define a `POST /story/suggest-next-sentences` endpoint that accepts:
  - Story ID, branch ID, last accepted sentence index.
  - Minimal recent history (IDs + chosen options + texts) and/or a reference to a stored summary.
  - Child profile and difficulty settings.
- Response returns:
  - 5 candidates with generator scores and ranker scores.
  - Safety flags.
  - Indices/IDs for the 2 recommended options.
- **Prompt and suggestion caching**:
- **Prompt context cache**:
  - Maintain serialized, reusable prompt fragments (system preamble, story summary, early turns) keyed by story ID + branch ID + last stable step.
  - When user advances one step, reuse the cached prefix and append only the last choice and query.
- **Suggestion cache**:
  - Where the full context (to a given step) matches a previous call, reuse the 5 candidates and rankings instead of hitting the models again (e.g., when user navigates back to an unchanged sentence and taps "regenerate" with identical context).
- Track cache hit/miss statistics and approximate token savings.
- **Two-model configuration via OpenRouter**:
- Configure the primary generator and secondary ranker as separate OpenRouter routes/presets within the existing client abstraction.
- Centralize model names, temperature, penalties, and rate limits so they can be adjusted without touching feature code.
- **Performance & fallbacks**:
- Apply debouncing and idempotency keys to avoid duplicate work if requests are retried or the user taps quickly.
- Fallback paths:
  - If Stage 2 fails, fall back to Stage 1 self-scores and a simpler selection rule.
  - If Stage 1 fails, allow the child to continue with their own sentence and possibly skip AI suggestions temporarily.
- **Telemetry and cost tracking**:
- Log per-call token usage and latency separately for generator and ranker.
- Track cost per sentence and per story, with and without cache hits, to quantify savings.
- Expose aggregated metrics (e.g., “median tokens/turn by story length bucket”) to guide prompt and cache tuning.

## 5. Front-End Architecture (Flutter) and State Management

- **Feature module**:
- Create a dedicated feature module (e.g., `story_companion`) with clear separation of `presentation`, `application`, and `domain` layers.
- **State model**:
- Use a robust state management approach (e.g., Riverpod/Bloc/Cubit) to track current `StorySession`, current sentence index, pending suggestions, loading/error states, and voice recording/recognition state.
- Maintain a local mirror of `PreferenceTrace` so the UI can react (e.g., showing badges like "You like silly ideas!").
- Design events/actions such as `StartStory`, `AcceptSuggestion`, `SubmitUserSentence`, `EditSentence`, `DeleteSentence`, `NavigateToSentence`, `RegenerateSuggestions`, and `PlayFromSentence`.
- **View models & mappers**:
- Map domain `SentenceNode` structures into UI-friendly models that include TTS playback status, animation cues, and selection state.

## 6. Core Story-Building UX

- **Main story-building screen**:
- Show the current sentence prominently, with prior sentences visible in a scrollable list.
- Directly beneath the current sentence, show the two AI suggestions as tappable cards.
- Provide a clear call-to-action for “Speak your own sentence” and an alternative keyboard input.
- **Accepting a suggestion**:
- On tap of a suggestion card, confirm selection with a delightful micro-animation (e.g., card expands, character reacts), store it as the accepted sentence, and append to the story.
- Log whether the child chose Option A, Option B, or "Write your own" for the preference trace.
- Immediately trigger fetching the next set of suggestions in the background while the child hears the selected sentence read aloud.
- **Authoring your own sentence**:
- Support voice input first: press-and-hold or tap-to-start, then show recognized text.
- Allow quick edit of the recognized text before finalizing.
- Once accepted, treat it like any other sentence, appended as a `SentenceNode` with `speaker = child` and `choiceType = write-in` for preference conditioning.
- **Feedback on choices**:
- Optionally show subtle tags like “Very silly!”, “Super surprising!”, derived from the combined scoring pipeline, to give meta-feedback without overwhelming.

## 7. Navigation, Scrolling, and Timeline Controls

- **Scrollable story timeline**:
- Implement a vertical scroll list of sentences, with the “active” sentence visually highlighted.
- Allow swipe left/right or dedicated arrow buttons to move between sentences without scrolling.
- **Jumping and playback**:
- Provide a simple “Play from here” control to hear the story read aloud from any selected sentence onward.
- Maintain a clear breadcrumb or header indicating where in the story the child currently is (e.g., “Sentence 5 of 18”).
- **Story overview**:
- Add an optional overview screen showing story length, themes, and a quick summary, enabling parents to get a snapshot.

## 8. Editing, Deleting, and Branching UX

- **Edit sentence flow**:
- Tap on a sentence to reveal options: `Edit`, `Delete`, `Regenerate suggestions from here`.
- Editing allows inline text editing; on save, mark all subsequent sentences as “out of date” and visually dim them.
- **Branch creation**:
- When the user proceeds after editing a past sentence, create a new branch:
  - Option A: Hide old branch by default but keep it accessible via a subtle branching indicator.
  - Option B: Keep a linear view but tag older, invalidated sentences as part of an “old version” for historical reference.
- Ensure that the backend understands which branch is active so that cached context and cache keys line up with the active branch.
- **Deletion**:
- Deleting a sentence removes it and all subsequent sentences in the active branch (with clear confirmation and parent-friendly language).
- Allow undo for a short period.
- **Regeneration**:
- Provide a one-tap action to “Try new ideas” from a given sentence, regenerating the 2 suggestions based on the context up to that point (and using cached context where possible).

## 9. Voice Input, TTS, and Audio UX

- **Voice capture**:
- Integrate with the existing speech recognition pipeline; design a child-friendly recording UI with clear visual feedback (waveform, timer, big mic button).
- Handle noisy environments with guidance (e.g., tips if confidence is low).
- **Transcription review**:
- Show recognized text clearly, with large fonts and immediate ability to fix small mistakes.
- Indicate recognition confidence subtly; suggest re-recording if confidence is very low.
- **Text-to-speech**:
- Use existing TTS infrastructure to read back:
  - Each new sentence when accepted.
  - The entire story or from any sentence on command.
- Consider multiple voices or a signature “story narrator” voice.
- **Audio storage**:
- Decide whether to store raw voice recordings and/or TTS audio for replay; handle storage limits and privacy.

## 10. Safety, Guardrails, and Parental Controls

- **Content safety**:
- Combine prompt-level constraints, an LLM safety classifier, and, if necessary, a lightweight on-device filter (e.g., banned-word list) to ensure age-appropriate content.
- Ensure the model avoids sensitive topics and provides gentle redirections when the story context pushes toward unsafe themes.
- **Profile-aware behavior**:
- Use child profile settings (age, reading level, sensitive topics) to parameterize prompts and filters.
- **Parental tools**:
- Provide a parent-only view or control panel where parents can:
  - Review stories.
  - Export stories (PDF, text, or shareable link).
  - Adjust allowed topics/tones (e.g., “no spooky stuff”).
- **Privacy & data retention**:
- Specify how long stories are stored, whether they leave the device, and how data is anonymized in logs.
- Ensure compliance with COPPA and your existing privacy policies.

## 11. Reward Systems, Motivation, and Delight

- **Positive reinforcement**:
- Add badges/celebrations when children reach milestones (e.g., “10 sentences!”, “First story completed!”, “Trying your own idea 3 times in a row”).
- **In-story companions**:
- Optionally integrate a character guide (mascot) that reacts to sentences and explains why suggestions are fun or interesting.
- **Visuals and formatting**:
- Support simple illustrations or thumbnails per story (hooking into your AI art pipeline later).
- Use playful typography and subtle animations that don’t distract from reading.

## 12. Analytics, Cost, Experimentation, and Iteration

- **Key metrics**:
- Track story length, session duration, suggestion acceptance rate, frequency of user-authored sentences, edit/delete patterns, and per-story/per-sentence token usage.
- **Caching and cost analytics**:
- Instrument cache key reuse, average size of cached prefixes, and hit/miss rates for both generator and ranker.
- Build a simple dashboard or log view showing approximate cost savings from caching and two-stage ranking compared to a naive single-model baseline.
- **LLM evaluation loop**:
- Periodically review anonymized logs of suggestions vs. chosen sentences to refine prompts, scoring weights, preference conditioning, and to decide where the ranker adds the most value.
- **A/B tests**:
- Experiment with different generator prompts (e.g., more humorous vs. more gentle), different ranker objectives, and different ways of surfacing preference summaries to the models.

## 13. Implementation Phases (With Caching and Two-Stage Scoring from Day One)

- **Phase 1 – Core loop MVP with cache-ready design**:
- Implement story models (`StorySession`, `SentenceNode`, `AlternativeSuggestion`, `InteractionMeta`, `PreferenceTrace`) and local persistence.
- Implement a basic `StorySuggestionService` using the existing OpenRouter client, a stable system preamble, and a rolling story summary, plus a single generator model that already outputs 5 candidates with self-scores.
- Create the basic story-building UI with two suggestions, user-authored sentences (text + voice), linear navigation, TTS playback, and minimal safety constraints.
- Instrument basic token usage logging to get an early read on cost and hint at where the ranker can help.
- **Phase 2 – Two-stage ranking, preference conditioning, and smarter caching**:
- Introduce the small ranker model and integrate the two-stage pipeline (generator + ranker) behind `StorySuggestionService`.
- Add explicit `PreferenceTrace` and incorporate it into both prompts.
- Introduce provider-level caching (if supported) using stable cache keys and prompt fragments, and refine local prompt reconstruction.
- Tune scoring weights and selection rules based on early usage data and cost/latency observations.
- **Phase 3 – Editing, branching, and polish**:
- Add robust editing, deletion, branching behavior with clear visual indicators and regeneration from any point.
- Ensure caching and cache keys correctly follow branches and invalidate when upstream context changes.
- Add mascot/companion behaviors, celebratory animations, and improved audio UX.
- **Phase 4 – Analytics & advanced optimization**:
- Integrate deeper analytics and A/B testing for prompt variants, cache strategies, and ranker configurations.
- Iterate on prompt structure, caching horizons, and ranker behavior to minimize cost while preserving creativity and delight.

## 14. Engineering Task Breakdown (High-Level Todos)

- **Story model & persistence**: Implement `StorySession`, `SentenceNode`, `AlternativeSuggestion`, `InteractionMeta`, and `PreferenceTrace` models plus local storage.
- **Generator & ranker pipeline**: Build `StorySuggestionService` with a primary generator model, secondary ranker model, prompt construction, suggestion scoring, and safety filtering using existing OpenRouter infrastructure.
- **Prompt and suggestion caching**: Implement local and provider-level prompt/context caching, suggestion caching, and telemetry for cache performance and token savings.
- **Story companion UI**: Create the main story-building screen with suggestions, input modes (voice + text), navigation controls, and subtle preference feedback to the user.
- **Editing & branching UX**: Implement edit/delete flows, branch handling, regeneration from arbitrary points in the story timeline, and ensure backend context/caching follow the active branch.
- **Voice & TTS integration**: Wire up voice input, transcription review, and story playback, leveraging existing pipelines.
- **Safety & parental controls**: Implement multi-layer safety checks for suggestions and add parental review/export tools.
- **Analytics, cost tracking & iteration**: Add telemetry for story usage, suggestion choices, token usage, cache behavior, and build feedback loops for prompt, UX, and cost tuning.

### To-dos

- [ ] Design and implement StorySession, SentenceNode, and AlternativeSuggestion data models plus local persistence for stories.
- [ ] Implement StoryLLMClient with prompt construction, LLM calls, suggestion scoring, and safety filtering.
- [ ] Build the core story-building UI with current sentence view, two suggestion cards, and user sentence input (text and voice).
- [ ] Add sentence editing, deletion, branching logic, and regeneration from arbitrary points in the story timeline.
- [ ] Integrate voice recognition and TTS playback throughout the story companion flow.
- [ ] Implement multi-layer safety checks for suggestions and add parental review/export controls.
- [ ] Add telemetry for story usage and suggestion choices, and set up feedback loops for prompt and UX tuning.