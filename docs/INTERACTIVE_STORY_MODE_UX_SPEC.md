## Interactive Story Mode – One-Sentence-at-a-Time UX Spec

### 1. Design Context and Goals

- **Overall purpose**: Create a **live, co-authored story experience** where a child (optionally with a parent) and the AI build a story **one sentence at a time**. The child feels like the *director* of the story, not a passenger, and the AI feels like an emotionally intelligent improv partner.
- **Target users**:
  - Primary: Children in Xen Words’ core age range (same band as the existing story reader), across a spectrum of reading/speaking confidence.
  - Secondary: Parents, siblings, and adults who “always wished they had this as a kid” and want to play in the same space.
- **Core feelings we want to produce**:
  - **Ownership**: “This is *my* story, I’m making it up as I go.”
  - **Delight & surprise**: “The story keeps doing magical things I didn’t expect but that feel right for me.”
  - **Psychological safety**: Even when there is suspense or tension, the experience feels emotionally safe and age-appropriate.
  - **Growth & curiosity**: The story gently invites the child to stretch—new ideas, new emotions, new perspectives—without overwhelming them.
  - **Family connection**: When used together, it feels like a new kind of social, creative play, not just “kid alone with a screen.”
- **Learning / values goals (high-level)**:
  - Normalize **struggle, trying again, and asking for help**.
  - Encourage **curiosity, imagination, and perspective-taking**.
  - Support **language growth** (vocabulary, expressive language) as a side effect of play.
  - Respect **parent-configured values** (e.g., tone limits, sensitive topics) and offer hooks for long-term development goals.

This UX spec focuses on the **front-end experience and flows** and intentionally exposes **hooks for model conditioning** (values, preferences, ratings) that the LLM spec will use.

---

### 2. Core Loop – “Spotlight Sentence” Interaction

#### 2.1 Mental model

- The story is a **vertical timeline** of sentences.
- At any moment there is **one “spotlight sentence”** that the child is working on.
- At the spotlight, the child can:
  - **Pick one of two AI suggestions**, or
  - **Speak / type their own sentence**.
- After committing that sentence, the story advances, and the next spotlight appears.

#### 2.2 Main elements on the core screen

- **Story timeline** (top area, scrollable):
  - Past sentences displayed as readable text in “storybook paragraphs”.
  - Subtle visual indicators:
    - Icon or small label for **speaker**: child, AI, parent cameo.
    - Light “vibe tag” badge (e.g., *silly*, *brave*, *cozy*, *mysterious*).
  - Sentences authored by the child are gently highlighted (e.g., faint glow or underline).

- **Spotlight panel** (fixed middle section):
  - Shows the **current sentence context**:
    - Last accepted sentence (read-only).
    - If useful, a short prompt like “What happens next?”
  - Includes a **character/world visual** that can react to accepted sentences (for future animation/art integration).
  - Displays the **Story Tension Meter** (simple visual bar or emotive icons) to give the child a sense of how “intense” things are right now.

- **Choice area** (bottom section):
  - **Suggestion A card**:
    - Sentence text.
    - Vibe icon (e.g., sparkle, heart, magnifying glass).
    - Optional micro-tag (e.g., “curious twist”, “big feeling moment”).
  - **Suggestion B card**:
    - Same structure, with a contrasting vibe.
  - **“Tell it yourself” control**:
    - Primary: large, friendly **mic button**: “Say your idea”.
    - Secondary: smaller text input icon: “Type your idea”.
  - **Emotional rail** (optional but important control):
    - Simple toggle/slider like: **Calmer – Just right – More exciting**.
    - Used occasionally or always visible, depending on UX tuning.

---

### 3. Opening Flow – “Tonight’s Story Mission”

#### 3.1 Entry point

- From the main app (dashboard / story hub), child taps a **“Create Your Story”** or **“Story Lab”** entry point.

#### 3.2 Mission setup screen

Goal: Make starting a story feel intentional and special, while quietly feeding the backend with parameters.

Elements:

- **Title**: “Tonight’s Story Mission” (copy can be varied).
- **Mood selector** (child-facing):
  - Pill buttons or card choices: *Silly*, *Brave*, *Cozy*, *Mystery*.
  - Each with a simple icon and 1-line description.
- **Companion character**:
  - Pick from a small cast (e.g., fox, robot, dragon, sibling avatar).
  - Each has a personality blurb.
- **Story setting** (optional / can be auto-suggested):
  - Simple options: *Forest*, *Space*, *Underwater*, *School*, *Dreamland*.
- **Hidden learning hooks**:
  - In the background, the system:
    - Fetches the child profile (age, reading level, word mastery).
    - Selects target words / language focus for this session.
    - Records parent-configured preferences/values for later model conditioning.

Actions:

- **Primary CTA**: “Start Story”.
- **Optional parent-only entry**:
  - Small “Parent settings” link (requires parent gate) to configure:
    - Tone boundaries (e.g., no spooky).
    - Values focus for this story (e.g., *persistence*, *kindness*, *sharing*).

---

### 4. Core Loop UX – Step-by-Step

#### 4.1 State: idle on spotlight sentence

UI:

- Context sentence shown in spotlight panel.
- Suggestion A and B cards visible (placeholder skeleton if still loading).
- Mic button and text input icon available.
- Tension meter shows current state.
- Emotional rail (if present) defaults to last chosen setting (or “just right”).

Behavior:

- If suggestions are not yet loaded:
  - Show animated loading placeholders inside the suggestion cards.
  - Child can still tap mic to author their own sentence immediately.

#### 4.2 Choosing an AI suggestion

- **Tap on Suggestion A/B**:
  - Card grows slightly, background character reacts (simple animation).
  - Immediate TTS playback of the chosen sentence in narrator voice.
  - UI feedback:
    - Suggestion card moves into the story timeline as the **new committed sentence**.
    - The spotlight panel scrolls to place the new sentence in the correct position and sets up the next spotlight.
  - Data captured:
    - Which option (A/B).
    - Candidate metadata (scores, vibe tags, tension delta).
    - Emotional rail value at the moment of choice.

#### 4.3 Authoring your own sentence (voice)

- **Tap mic button**:
  - Screen enters a **recording state**:
    - Large waveform/mic animation.
    - Clear copy: “Tell what happens next!”
    - Option to cancel (X) or finish.
  - On stop:
    - Show ASR result in large text.
    - Offer **quick fix**:
      - Simple inline text field to adjust words.
      - “Looks good!” button for kids who don’t want to edit.
  - On confirmation:
    - The text becomes the new sentence in the story timeline.
    - TTS optionally re-reads their sentence in narrator voice (with an indicator that it’s “your line”).
  - Data captured:
    - Raw audio (if stored), transcription, final edited text.
    - Marked as `speaker = child`, `origin = write-in`.

#### 4.4 Authoring your own sentence (text)

- **Tap text icon**:
  - Show a simple, **low-friction text entry**:
    - Big, high-contrast field.
    - Helpful prompt text: “Type your sentence”.
  - On submit:
    - Same as voice path, but without ASR step.

#### 4.5 Emotional rail interaction

- Emotional rail UI (e.g., 3-option segmented control):
  - Icons and labels: **Calmer**, **Just right**, **More exciting**.
  - Optionally, a tooltip on first use: “You can choose how intense this part feels.”
- Behavior:
  - When the child changes it:
    - Store in local `PreferenceTrace`.
    - Immediately influence the next set of candidate suggestions (via backend).
  - UI feedback:
    - A tiny toast: “Okay, we’ll make this part a little more exciting (but still safe).”

---

### 5. Navigation, Editing, and Branching

#### 5.1 Viewing and scrolling the story

- The timeline scrolls vertically:
  - Current spotlight sentence is always visually distinct (highlighted bar, border, or background).
  - Past sentences are readable but slightly lower contrast.
- Quick navigation:
  - Small “Sentence X of Y” indicator near the spotlight.
  - Optionally, up/down arrows or swipe hints for younger users.

#### 5.2 Editing a past sentence

- **Tap on a past sentence** (or long-press):
  - Show a small action bar:
    - `Edit`
    - `Delete from here`
    - `What if this went differently?` (branch)
- **Edit flow**:
  - Enter an inline editor:
    - For text: show the sentence in an editable field.
    - For a child-authored voice line: show text and allow re-record + re-edit.
  - On save:
    - All subsequent sentences are visually dimmed and marked as “out-of-date”.
    - A short explanation banner: “You changed this part; the rest of the story is waiting to be updated.”

#### 5.3 Branching: “What if this went differently?”

- When child taps `What if this went differently?`:
  - UI explains in child-friendly language:
    - “We’ll make a **new path** from here. Your old version is still saved.”
  - Visually, a **subtle branch indicator** appears:
    - E.g., a tiny “fork” icon on the edited sentence.
  - The active branch continues forward using the familiar spotlight loop:
    - Suggestion A/B + “tell it yourself” from that point on.
  - Parent view (in parent mode) can show:
    - Branch overview, for reviewing how the story evolved.

---

### 6. End-of-Story Flows and Multi-Day Rituals

#### 6.1 Story completion

- Conditions for “complete”:
  - Explicit end event from the model (“This feels like a natural ending”), or
  - Reaching soft limits on length / time, or
  - Child/parent triggers “Wrap up”.
- Completion screen:
  - **Time-lapse playback**:
    - Quick animation of sentences appearing in order.
    - Child-authored sentences glow or get a small badge (“Your idea!”).
  - **Highlights**:
    - “Moments you changed the story.”
    - “Brave moments” or “Kindness moments”, depending on values.
  - **Celebration**:
    - Animations, audio reward, simple badge (e.g., “First Co-Created Story”).

#### 6.2 “Plant a Seed for Next Time”

- After completion:
  - Prompt: “Want to plant a seed for your next story?”
  - Options for seed:
    - Short voice clip (“Next time, I want a shy dragon and a tiny rocket.”).
    - Simple text or drawing (photo of a drawing).
  - Seeds are:
    - Saved to the profile.
    - Used as strong conditioning for the **opening of future stories**.

---

### 7. Parent-Facing Surfaces and Backchannel

#### 7.1 Parent view entry points

- Accessible via:
  - Parent-only dashboard section, or
  - “Review story” / “Parent notes” button after a story session (behind parent gate).

#### 7.2 Per-story parent view

- Shows:
  - Story text with clear marking of child-authored vs AI-authored vs parent-authored lines.
  - Simple stats:
    - Number of sentences.
    - % child vs AI contributions.
    - Emotional balance summary (e.g., “mostly cozy, some brave moments”).
  - **Values lenses**:
    - E.g., tags like *persistence*, *kindness*, *asking for help* where the story hit those notes.

#### 7.3 Parent backchannel feedback

- For each story, parents can optionally provide:
  - **Overall rating** (1–5) for:
    - “Fit for my child.”
    - “Emotional tone.”
    - “Learning / growth moment quality.”
  - **Behavior notes** (short structured input):
    - E.g., checkboxes: “Child was very engaged”, “Child was anxious at scary parts”, “Child wanted more silliness”.
  - **Values / goals preferences** for future stories:
    - E.g., sliders or multi-select:
      - More: *persistence*, *kindness*, *friendship*, *exploring feelings*, *trying new things*.

This information is stored as **backchannel data**, not shown to the child, and is used to **condition future story generation and ranking**.

---

### 8. UX Hooks for LLM Conditioning and Self-Rating

The UX surfaces the following data that the model pipeline should use:

- **Child-facing choices**:
  - A/B suggestion selections per step.
  - Frequency of “tell it yourself” vs AI suggestions.
  - Emotional rail adjustments over time.
  - Which “imagination challenges” (future feature) are taken or skipped.
- **Parent-facing inputs**:
  - Per-story ratings (fit, tone, learning quality).
  - Behavior observation tags.
  - Values/goal preferences.
- **System-derived metrics**:
  - Tension curve over the story.
  - Distribution of emotional beats (e.g., moments of struggle, repair, celebration).

In the future **LLM prompt + scoring spec**, we should:

- Condition prompts with:
  - A compact trace of **child preferences and behaviors**.
  - A compact history of **parent ratings and value preferences**.
  - Selected **exemplar snippets** from past highly-rated stories (with metadata) as style anchors.
- Have the LLM:
  - **Self-rate** its suggestions on axes aligned with product values (e.g., growth mindset, kindness, curiosity) in addition to creativity/coherence.
  - Use these self-ratings, plus the ranker, to choose which candidates get surfaced as A/B options.

This spec intentionally keeps the UX **transparent and simple** for the child while giving engineering/ML a **rich, nuanced signal space** to work with as we refine the models and scoring.

---

### 9. Implementation Phasing for UX

- **Phase 1 – Vertical slice**:
  - Mission setup screen with mood + basic companion choice.
  - Core loop with spotlight sentence, A/B suggestions, and “tell it yourself” (voice + text).
  - Simple completion screen (no seeds yet).
- **Phase 2 – Emotional rail and richer feedback**:
  - Add emotional rail and wire it to backend preference trace.
  - Visualize tension in a simple, child-comprehensible way.
- **Phase 3 – Editing, branching, and time-lapse**:
  - Add edit/delete/branch flows and the “what if this went differently?” UX.
  - Implement end-of-story time-lapse playback.
- **Phase 4 – Parent backchannel and seeds**:
  - Build parent story review, ratings, and values configuration.
  - Implement “plant a seed for next time” and use it in story openings.
- **Phase 5 – Deep refinement**:
  - Tune microcopy, animations, art integration, and delightful edge cases based on real family testing.


