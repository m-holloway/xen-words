## Interactive Story Mode – LLM & Pipeline Design

### 1. Design goals and constraints

- **Child-as-coauthor, not passenger**: The LLM should treat each turn as *adding to the child’s story*, not overwriting it. It must respect what the child already said, and build forward with curiosity.
- **One-sentence, low-friction turns**: Core loop is *one sentence at a time*, with optional suggestions. Latency, brevity, and clarity matter more than maximal creativity per turn.
- **Values-aware but not didactic**: Stories should be gently aligned with parent/guardian values (kindness, perseverance, curiosity, etc.) without turning into lectures.
- **Respect existing infrastructure**:
  - Reuse `StoryGenerationRequest` / `GeneratedStoryRecord` and the OpenRouter JSON story pipeline where possible.
  - Align with Python `StoryGenerator` / `StoryRequest` models and spaced-repetition word placement where that infrastructure is in play.
- **Cost-aware**: Prefer light-weight “sentence suggestion” calls over full-regeneration. Reserve full chapter/beat JSON calls for checkpoints and summaries.
- **Future-proof for conditioning**: The design must leave room to:
  - Condition on past stories + ratings.
  - Include a parent values/backchannel block.
  - Include basic reading analytics (what kids reread, where they drop off, etc.).

---

### 2. High-level pipeline: one-sentence co-creation loop

At a high level, interactive mode layers on top of the existing JSON story pipeline:

1. **Session bootstrap**
   - Input: `StoryGenerationRequest` (reading level, band, minutes, parent prompt, child context, cast, profile, etc.), plus *interactive mode flag*.
   - LLM call:
     - Reuse a slightly adapted version of `OpenRouterStoryClient.generateStoryPayload` to generate:
       - A *lightweight skeletal outline*: title, summary, 8–16 high-level beats (1–2 sentences), themes, tone.
       - A *word-focus plan* (optional) aligned with existing `focus_words` and spaced repetition.
     - Output stored into a `GeneratedStoryRecord` (like today) **and** a separate `InteractiveStoryPlan` (see schema below).
   - Purpose: Give the system a north-star arc without over-specifying the exact one-sentence steps.

2. **Interactive loop (per child turn)**
   - Input each turn:
     - `story_state` (sentences so far, planned beats, current beat index, any unresolved branches).
     - `child_turn`:
       - What the child said / chose (text or structured choice).
       - VAD/speech metadata (optional).
     - `context`:
       - `StoryGenerationRequest` fields (level, minutes, child context).
       - Parent values / goals (see §4).
       - Optional: shortlist of *reference exemplars* (prior highly-rated snippets).
   - LLM call: “next sentence suggestion” model (fast, low-cost).
     - Returns:
       - 1–3 **candidate next sentences**.
       - Lightweight self-ratings (values alignment, tension level, novelty, coherence with plan).
       - A small `designer_note` to guide UI/coach phrasing (never shown raw to child).
   - App logic:
     - Ranks or filters candidates using:
       - Child’s reading level and target difficulty band.
       - Parent/values alignment.
       - Internal guardrails (no violence, etc.).
     - Surfaces 1–3 options or a single suggested next sentence to parent/child.
     - When the user commits (chooses / speaks / edits), we:
       - Append the final sentence into `story_state`.
       - Update per-beat word counts, difficulty tracking, and tension score.

3. **Checkpointing and summarization**
   - Every N sentences or when a “beat boundary” is crossed:
     - Generate/update:
       - Short canonical **beat summary**.
       - Optional **panel art prompt fragment** (if art is enabled).
   - Optionally call a slower “checkpoint model”:
     - to fix coherence issues,
     - to re-steer toward values and goals,
     - to compress prior context for future turns.

4. **Session close**
   - LLM call: “closing pass” model to:
     - Smooth the ending: ensure emotional closure and wholesome tone.
     - Suggest a **session reflection line** for the coach (“I loved how you kept trying when…”).
   - Persist:
     - Final `StoryChapter` beats (synthesized from the interactive log).
     - `GeneratedStoryRecord` with:
       - `childRating` (post-session).
       - `readMoments`.
       - Interactive metadata (turn count, choices, tension curve).

---

### 3. Core data structures for interactive mode

We introduce conceptual models (can be Dart or Python backed) that sit *beside* existing story models:

#### 3.1 `InteractiveStoryPlan`

High-level arc produced at session start (via JSON story call or a lighter model):

```json
{
  "id": "plan_123",
  "story_id": "story_abc",
  "title": "The Cloud Lantern",
  "beats": [
    {
      "id": "beat_1",
      "goal": "Introduce protagonist and cozy-but-curious mood",
      "target_words": ["cloud", "soft"],
      "tension_hint": 0.1,
      "value_focus": ["curiosity", "warmth"]
    }
  ],
  "global_themes": ["friendship", "courage"],
  "tone": "warm-adventurous",
  "reading_band": { "grade_band": "K-1", "notes": "…" }
}
```

This plan is **advisory**: the interactive loop can diverge, but the LLM uses it as a soft constraint.

#### 3.2 `InteractiveStoryTurn`

Log of each child/AI turn:

```json
{
  "turn_index": 7,
  "speaker": "child|parent|coach|system",
  "input": {
    "utterance_text": "Then the turtle finds a glowing rock",
    "choice_id": null,
    "raw_audio_path": null
  },
  "llm_candidates": [
    {
      "id": "cand_1",
      "sentence": "The glowing rock hummed softly, like it had a tiny heartbeat inside.",
      "scores": {
        "values_alignment": 0.92,
        "tension": 0.4,
        "reading_level_fit": 0.9,
        "novelty": 0.6,
        "coherence_with_plan": 0.85
      },
      "tags": ["sensory", "mystery"],
      "designer_note": "Leans into wonder without fear; hint of mystery but not scary."
    }
  ],
  "chosen_sentence": "The glowing rock hummed softly, like it had a tiny heartbeat inside.",
  "beat_id": "beat_3"
}
```

This log is the raw material for:
- rebuilding a `StoryChapter` later,
- analyzing what kids loved,
- feeding exemplars back into future prompts.

#### 3.3 `InteractiveStorySessionContext`

Structured context passed into almost every LLM call:

```json
{
  "story_id": "story_abc",
  "plan_id": "plan_123",
  "profile_id": "child_1",
  "reading_level": 2,
  "reading_band": { "grade_band": "K-1" },
  "parent_prompt": "A cozy adventure with a shy turtle who learns to be brave.",
  "child_context": "Loves turtles and space; sometimes worried about new things.",
  "cast_context": "Story Friends to include…",
  "values_goals": {
    "encouraged_traits": ["persistence", "kindness", "curiosity"],
    "avoid_content": ["bullying", "sad endings"],
    "emotional_safety_rules": [
      "Challenge but do not overwhelm.",
      "Always resolve scary elements with warmth."
    ]
  },
  "exemplar_snippets": [
    {
      "text": "The moon peeked between the clouds like a shy friend playing hide-and-seek.",
      "child_rating": 5
    }
  ]
}
```

---

### 4. Parent backchannel and values encoding

We introduce a **parent-facing configuration surface** whose payload is injected as structured JSON into the system prompt for the interactive mode models.

#### 4.1 Parent goals / values schema

```json
{
  "values_goals": {
    "core_values": ["kindness", "courage", "curiosity"],
    "skill_focus": ["trying_new_things", "asking_for_help"],
    "tone_preferences": {
      "humor": "gentle|silly|low",
      "tension": "low|medium|high",
      "pace": "cozy|brisk"
    },
    "content_boundaries": {
      "avoid": ["bullying", "realistic injury", "death of family members"],
      "soften": ["monsters", "storms"]
    },
    "family_context_notes": "Short free-text field about current anxieties, goals, or sensitivities."
  }
}
```

This lives in parent UX and is **never shown to child**; the LLM sees it in a dedicated “Values & Constraints” block in the system prompt.

#### 4.2 LLM self-rating against values

Every “next sentence” response includes a lightweight self-rating:

```json
{
  "sentence": "…",
  "scores": {
    "values_alignment": 0.94,
    "tension": 0.35,
    "reading_level_fit": 0.9
  },
  "rationale": {
    "values_alignment": "Shows perseverance and gentle support.",
    "tension": "Moment of curiosity, not fear."
  }
}
```

App logic can:
- enforce hard constraints (drop candidates with low values_alignment),
- nudge selection toward parent-preferred tension/pace bands.

---

### 5. LLM prompts and JSON schemas

#### 5.1 Session bootstrap: story plan prompt

**System prompt sketch (conceptual):**

- Role: “You are a children’s story architect helping plan an interactive story session.”
- Inputs:
  - `StoryGenerationRequest` (as today, via JSON).
  - Parent values / goals.
  - Optional exemplar snippets (top-rated past sentences).
- Task:
  - Propose:
    - Title, summary.
    - 8–16 beats with goals, target tensions, and value-focus tags.
    - 4–6 `focus_words` (aligned with current reading band).
  - Return JSON only, no commentary.

**Output JSON schema (simplified):**

```json
{
  "title": "…",
  "summary": "…",
  "focus_words": ["…"],
  "beats": [
    {
      "id": "beat_1",
      "goal": "…",
      "approx_sentences": 2,
      "tension_target": 0.3,
      "values_tags": ["curiosity"]
    }
  ],
  "themes": ["friendship", "courage"],
  "tone": "warm-adventurous"
}
```

This can either:
- be a **new endpoint** in Dart using `OpenRouterStoryClient._callModelWithMessages` with a different `systemPrompt`, or
- be a sub-mode of the existing story generation call keyed by `request.metadata.interactive_mode = true`.

#### 5.2 Turn-level “next sentence” prompt

This is a new, lighter-weight endpoint. Conceptual API:

- Input JSON (user message content):

```json
{
  "context": { /* InteractiveStorySessionContext */ },
  "plan": { /* InteractiveStoryPlan, maybe truncated */ },
  "recent_turns": [
    { "speaker": "child", "text": "…" },
    { "speaker": "system", "text": "…" }
  ],
  "current_beat": {
    "id": "beat_3",
    "goal": "Introduce mysterious but safe magical object.",
    "tension_target": 0.4,
    "values_tags": ["curiosity"]
  },
  "child_event": {
    "utterance_text": "Then the turtle finds a glowing rock.",
    "choice_id": null
  }
}
```

- Expected JSON output:

```json
{
  "candidates": [
    {
      "id": "cand_1",
      "sentence": "The glowing rock hummed softly, like it had a tiny heartbeat inside.",
      "scores": {
        "values_alignment": 0.92,
        "tension": 0.4,
        "reading_level_fit": 0.9,
        "novelty": 0.6,
        "coherence_with_plan": 0.85
      },
      "rationale": {
        "values_alignment": "Shows curiosity and wonder without fear.",
        "reading_level_fit": "Uses mostly level-2 familiar words with one stretch word: 'heartbeat'."
      },
      "tags": ["sensory", "mystery"]
    }
  ],
  "suggested_beat_transition": {
    "stay_on_beat": true,
    "reason": "Beat goal not fully satisfied; one more sentence recommended."
  }
}
```

**System prompt key ideas:**
- Emphasize:
  - One, clear, read-aloud friendly sentence per candidate.
  - Keep structure grounded in kid’s previous line and beat goal.
  - Align with `values_goals` and reading level.
- Forbid:
  - Major plot twists that contradict child input.
  - Content violating `content_boundaries`.

#### 5.3 End-of-session smoothing prompt

Input:
- Full `InteractiveStoryTurn` log (optionally summarized).
- Values / goals.

Task:
- Retell the ending 2–3 sentences to ensure closure and warmth.
- Propose a one-line parent reflection.

Output JSON:

```json
{
  "final_sentences": [
    "…",
    "…"
  ],
  "coach_reflection_line": "I loved how you kept going even when the glowing rock was a little strange."
}
```

---

### 6. Integration with existing code

#### 6.1 Where this fits today

- **Dart side**
  - `StoryGenerationRequest` and `GeneratedStoryRecord` remain the primary persisted types.
  - Interactive mode adds:
    - A new `InteractiveStorySession` object (Dart) holding `plan`, `turns`, and `context`.
    - A light-weight service (`InteractiveStoryService`) that:
      - Calls a new backend route for:
        - story plan bootstrap,
        - per-turn “next sentence” suggestions,
        - end-of-session smoothing.
      - Updates local state and writes back to `StoryGeneratorService` / `StoryStorageService` at checkpoints.

- **Python side (genai/story_generator)**
  - Current `StoryGenerator` already:
    - Encodes beat structure, choice points, tone, and spaced repetition.
  - We can:
    - Add an **interactive mode handler** to `story_api.py`:
      - `/interactive/plan` → returns `InteractiveStoryPlan`.
      - `/interactive/next-sentence` → returns candidates as defined above.
      - `/interactive/finalize` (optional) → returns smoothed ending + reflection line.
    - Reuse `calculate_spacing_for_all_words` where we want target word pacing in interactive mode.

#### 6.2 Condition on prior stories and ratings

- For a given profile:
  - At session bootstrap, backend can fetch:
    - The top N `GeneratedStoryRecord`s by `childRating`, `readCount`, or recentness.
    - A few **short, highly-rated sentences** or beats.
  - Those become `exemplar_snippets` in `InteractiveStorySessionContext`.
  - The system prompt instructs the model:
    - “Gently echo the *feel* of these exemplars (tone, rhythm, warmth) without copying text.”

---

### 7. Safety, guardrails, and observability

- **Guardrails**
  - All turn-level endpoints must:
    - Validate JSON strictly (no free-form text).
    - Enforce content filters against `content_boundaries`.
  - Add a simple rule-based post-filter in Dart:
    - Drop candidates containing banned terms.
    - Fallback to a safe backup sentence if all candidates are rejected.

- **Observability**
  - Log (to disk, locally):
    - Model ID, latency, token estimates (following `OpenRouterStoryClient` style).
    - Anonymized metrics: per-session turns, candidate rejection rates, tension curves.
  - Periodically mine:
    - Top sentences by child rating.
    - Failure patterns (e.g., model over-indexing on certain tropes).

---

### 8. Next steps

- **Backend**
  - Implement `/interactive/plan`, `/interactive/next-sentence`, `/interactive/finalize` in `story_api.py`, reusing `StoryGenerator` where sensible.
  - Define Pydantic models mirroring `InteractiveStoryPlan`, `InteractiveStoryTurn`, and the candidate schema.
- **Flutter**
  - Add `InteractiveStorySession` model and service.
  - Integrate with UI flows defined in `INTERACTIVE_STORY_MODE_UX_SPEC.md`.
- **Tuning**
  - Pilot with a small set of families and use:
    - Parent values inputs,
    - Child ratings,
    - Reading analytics
    to refine prompts and value weights.


