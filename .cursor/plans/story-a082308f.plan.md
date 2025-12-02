<!-- a082308f-2b12-48ae-aebd-910e7322bd91 303db266-c38f-4bdd-870f-b2df6b78a68e -->
# Story Structure & Illustration Modes Plan

#### 1. Standardize Current Picture-Book Mode (16-Beat Grid)

- **Fixed beat count**
- Treat the current “Storybook with panels” mode as a **16-beat picture book**.
- Story generator system prompt will explicitly require **exactly 16 narration beats**, each beat being one page/panel.
- Each beat: target **60–120 words** (2–4 sentences), tuned by reading level.

- **Duration vs. word count**
- For each reading level, define a target **words-per-minute** band and map requested minutes → total word range:
- Level 2: ~110–130 wpm
- Level 3: ~130–150 wpm
- Level 4–5: ~150–170 wpm
- Compute `target_words`, then enforce:
- Total story words ∈ `[0.9 × target_words, 1.1 × target_words]`.
- Given 16 beats, use this to derive per-beat target (e.g., for Level 3, 20 min → ~2,600–3,000 words → ~160–190 words/beat, but we can cap beats to keep them readable).
- Add explicit constraints to the story system prompt: “You MUST produce exactly 16 beats and keep total words within [min,max].”

- **Panel art alignment**
- Panel description LLM must also be told that there are **exactly 16 beats** (even if some are very short) and always produce **16 panel briefs**.
- Panel art prompt and slicer assume **always 4×4 = 16 cells**, with unused beats allowed to be “blank” but we strongly prefer every beat to have some visual content in this mode.

- **UI/UX copy for parents**
- In Story Lab, label this mode something like **“Illustrated Storybook (16 pages)”**.
- When they pick duration, explain: “We’ll weave your idea into a 16‑page picture book; longer times mean more words per page, not more pages.”
- When they generate scene-by-scene art, clarify: “We’ll create a 4×4 grid of 16 panels, one for each page of the story.”

#### 2. Prepare for Additional Story Modes (Future)

- **Mode A: Picture Book (current, 16 panels)**
- Exactly 16 beats, one panel per beat.
- Strong art focus; best for ages ~4–8.

- **Mode B: Lightly Illustrated Story (fewer panels)**
- Beats: 12–24, but **only 4–8 panels** total.
- Panels are attached to:
- Key emotional moments (beginning, midpoint, climax, resolution), or
- Every N beats (e.g., every 3rd beat), chosen algorithmically.
- Story generator: similar duration/word rules, but art planner chooses which beats get illustrations.
- Reader UX:
- Reading flow stays per‑beat for narration.
- Art panel shows only when a beat is mapped to art; other beats show text only.

- **Mode C: Chapter Story (older readers)**
- Structure:
- **Chapters**: 3–6.
- Beats per chapter: 4–8.
- Illustration strategy:
- 1–3 panels per chapter (e.g., chapter opener, one big climactic scene).
- Story generator prompt:
- Must output chapters, each with its own beats and optional “chapter summary” for the parent.
- Reader UX:
- Story reader shows chapter navigation + fewer, more cinematic images.

- **Configuration surface**
- Add a **“Story Format”** picker to the Story Lab generator:
- Illustrated Storybook (16 pages)
- Lightly Illustrated Story
- Chapter Adventure (fewer pictures)
- For each format, show a short, concrete description: pages, approximate illustrations, and who it’s ideal for.

#### 3. Heuristics for Beats, Words, and Panels by Mode

- **Create a small configuration table** (in code) keyed by:
- Story format (PictureBook / LightlyIllustrated / ChapterStory).
- Reading level.

For each combination, store:

- `target_beats` (per story or per chapter).
- `beats_per_chapter` (for chapter stories).
- `words_per_minute` and `min_minutes`/`max_minutes`.
- `illustration_ratio` (e.g., 1 panel per beat, 1 panel per 3 beats, 2 panels per chapter).

The generator can then:

- Compute `target_words` from duration and `words_per_minute`.
- Decide **beats** and **per-beat word ranges**.
- Decide **how many panels** and which beats get them.

#### 4. Prompt-Level Changes to Enforce Structure

- **Story payload prompt**
- Add explicit fields in the JSON schema for:
- `beats` array length (exactly 16 for picture books in Mode A).
- Optional `chapter` grouping for Mode C.
- Include a clear, bold instruction section:
- “DO NOT change the number of beats. If you feel more beats are needed, merge details instead of adding beats.”

- **Panel description prompt**
- Reuse the new Story World character context, but:
- Begin with a short, clear explanation that character traits & outfits live in a canonical section and should NOT be repeated in full for every panel.
- For 16‑beat mode: “You MUST produce exactly 16 panel descriptions, one per beat, in story order.”

- **Validation & fallback**
- After story generation:
- Check beat count; if not 16, either:
- Ask the model in a short follow-up call to split/merge beats so that it becomes 16, **or**
- Run a lightweight local fix that splits long beats into two (for picture‑book mode only).
- After panel-description generation:
- Validate that exactly 16 descriptions were produced; if fewer, run a small repair (e.g., duplicate or interpolate nearby beats) while logging for debugging.

#### 5. Immediate Next Steps (Implementation Order)

1. **Lock current picture-book mode** to exactly 16 beats in the story prompt and panel‑description prompt, including word-count guidance and validation checks.
2. **Introduce a `StoryFormat` enum/config** in code (PictureBook16, LightIllustrated, ChapterStory) and thread it through the generator pipeline (even if only PictureBook16 is active in the UI at first).
3. **Add a simple format label to the UI** (“Illustrated Storybook (16 pages)”) and adjust copy around story length to explain that minutes control words per page, not page count.
4. **In a future pass**, wire up “Lightly Illustrated” and “Chapter Adventure” modes, with:

- Different `target_beats`, `illustration_ratio`, and prompts.
- Reader UI tweaks to handle non‑1:1 beat‑to‑image mapping.

This keeps the current product focused and predictable (16‑page picture books with one panel per page), while setting up a clear path to more flexible formats without redoing the core pipeline later.