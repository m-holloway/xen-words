## Mad Libs Darwin/Goedel Journal

### 2025-12-02 – Initial refinement experiments (Level 3)

- **Stories explored**
  - `A Playful Day in the Park` – friendship with a lonely pet in the park.
  - `Milo's Missing Balloon` – child + friend search for a lost balloon.
  - `Mia and the Lost Kite` – child + animal friend retrieve a lost kite from trees.

- **Process**
  - Generated templates with `inception/mercury` via `madlibs_story_generator.py`.
  - Ran population + heuristic + LLM judge experiments via `madlibs_story_evolver.py`.
  - Iteratively refined individual stories using `madlibs_story_refiner.py` (1–4 rounds).
  - Judge model: `inception/mercury` with scores for `overall`, `story_arc`, `character_engagement`, `emotional_warmth`, `curiosity_hooks`, `madlibs_usability`, `reading_level_fit`.

- **Observations**
  - 1–2 refinement rounds reliably turn “good scaffolds” into **strong, clean Level 3 picture-book arcs**.
  - Beyond ~3–4 refinements, changes become **local tweaks** (rephrasing, small detail shifts) with little net gain.
  - Stories are consistently cozy and safe, but skew toward a **narrow pattern**:
    - Lost/absent object or lonely animal,
    - Search/offer help,
    - Snack sharing / play / friendship moral.
  - Judge agrees with human sense of “solid, well-formed story,” but:
    - Does not strongly penalize generic arcs or on-the-nose morals.
    - Rewards emotional warmth and arc clarity more than **novelty** or **memorable weirdness**.

- **What feels missing in the best current stories**
  - At least one **distinctive, kid-memorable moment** (funny image, surprising beat).
  - A brief, meaningful **inner decision** for the child (“almost gave up, then chose the kinder/braver option”).
  - Stronger preference for **showing** the lesson through actions, instead of telling it explicitly.

- **Next-iteration hypotheses**
  - Upgrade generator prompt to:
    - Require one quirky/surprising image.
    - Require one small inner decision beat.
    - Forbid explicit moral sentences; rely on actions and scenes.
  - Upgrade judge prompt to:
    - Add `novelty`, `memorable_moment`, and `show_vs_tell` scores.
    - Weight these alongside `story_arc` and `emotional_warmth`.
  - Consider using a **different model as judge** to reduce bias toward Mercury’s default patterns.

### 2025-12-02 – Prompt upgrade pass (generator + judge)

- **Changes applied**
  - `madlibs_story_generator._system_prompt()` now:
    - Explicitly asks for:
      - At least one slightly surprising or vivid image that a child might remember.
      - One brief inner decision beat for the child character (choosing the kinder/braver option).
    - Forbids explicit moral sentences; requires lessons to be shown via actions/images.
  - `madlibs_story_evolver._judge_system_prompt()` now adds axes for:
    - `novelty`, `memorable_moment`, `show_vs_tell`, `character_depth`,
    - While keeping existing axes (story_arc, emotional_warmth, curiosity_hooks, etc.).

- **Intent**
  - Shift the generator away from “safe and generic” toward stories with:
    - A distinctive moment,
    - A small inner choice,
    - And less didactic phrasing.
  - Teach the judge to explicitly score and therefore favor:
    - Non-generic arcs,
    - Memorable beats,
    - Showing over telling,
    - Slightly richer inner life at kid scale.

### 2025-12-02 – First run with upgraded prompts (Mia and the Little Bird)

- **Config**
  - Generator:
    - Model: `inception/mercury`
    - Prompt version: `G1_novel_innerChoice_showDontTell`
  - Judge:
    - Model: `inception/mercury`
    - Prompt version: `J1_novelty_memorable_showDontTell_depth` (implicit in code).

- **Generation**
  - Base story: `madlib_story_level3_20251202_132647.*` – *Mia and the Little Bird*.
  - Arc:
    - Mia loves playing with a toy at a favorite place.
    - Notices a tiny bird with a drooping wing.
    - Brief inner near-mistake (almost drops bird) and correction via remembered kindness.
    - Cares for the bird, shares a snack; bird sings a memorable sound and flies away with colored sparkles.
  - Slots are concrete (toy, place, color, friend animal, snack, sound).

- **Refinement chain (3 rounds)**
  - 1st refinement: `...132647_refined_20251202_132700.*`
    - Judge scores (approx): overall 0.84; strong `story_arc`, `emotional_warmth`, `show_vs_tell`; decent `novelty`, `memorable_moment`, `character_depth`.
  - 2nd refinement: `...132647_refined_20251202_132700_refined_20251202_132709.*`
    - Slight variations in ordering/phrasing; no dramatic qualitative change; scores stay in same band.
  - 3rd refinement: `...132647_refined_20251202_132700_refined_20251202_132709_refined_20251202_132718.*`
    - Adds a bit more inner texture (“Mia felt a flutter in her heart…”, “gentle plan”, eyes sparkle).
    - Judge scores: overall ≈ 0.86; `show_vs_tell` and `character_depth` notably strong; `novelty` still moderate.

- **Qualitative takeaways**
  - Upgraded prompts **successfully introduced**:
    - A clear inner decision (almost drops the bird, then chooses kindness).
    - A more vivid central image (tiny bird, soft wing, glittering colored sparkles).
    - Better “show, don’t tell” behavior; no blunt moral sentences.
  - However, `novelty` remains moderate:
    - The high-level arc (hurt animal → kindness → recovery) is still familiar, though now more emotionally textured.
  - For future DG iterations on process:
    - Further emphasize “one standout twist or image” and “slightly unexpected turn” in both generator and judge prompts.
    - Consider a different judge model to push more strongly against generic patterns once basic safety and coherence are locked in.

### 2025-12-02 – Comparing Mercury vs Gemini 3 Pro as judges

- **Setup**
  - Template used: late-stage refined *Mia and the Lost Kite*:
    - `madlib_story_level3_20251202_122540_refined_20251202_122554_refined_20251202_122942_refined_20251202_122951_refined_20251202_123003.json`
  - Models:
    - Judge 1: `inception/mercury`
    - Judge 2: `google/gemini-3-pro-preview`

- **Scores**
  - Mercury judge:
    - `overall`: ~0.85, with high `story_arc`, `emotional_warmth`, `madlibs_usability`, solid `character_engagement`, and moderate `novelty`/`memorable_moment`.
  - Gemini 3 Pro judge:
    - `overall`: ~0.45, with:
      - Lower `story_arc`/`engagement`/`curiosity_hooks`,
      - Very low `novelty`/`memorable_moment`/`character_depth`,
      - High `reading_level_fit` (agrees it’s structurally appropriate).

- **Interpretation**
  - Mercury behaves as a **friendly structural + warmth judge**: good at filtering broken/unsafe stories and rewarding clean arcs and cozy tone.
  - Gemini 3 Pro behaves as a **strict taste critic**:
    - Much harsher on generic patterns and shallow inner life.
    - Effectively says: “This is fine and level-appropriate, but not remarkable.”

### 2025-12-02 – Refinement with Gemini 3 Pro as judge (Mia and the Little Bird)

- **Config**
  - Generator/refiner: `inception/mercury` with `G1_novel_innerChoice_showDontTell`.
  - Judge: `google/gemini-3-pro-preview`.
  - Base: `madlib_story_level3_20251202_132647.json` – *Mia and the Little Bird*.

- **3-step refinement chain**
  - 1st Gemini-judged refinement:
    - `...132647_refined_20251202_133436.*`
    - Scores: `overall` ~0.45, low `story_arc`/`novelty`/`character_depth`.
  - 2nd refinement:
    - `...133436_refined_20251202_133505.*`
    - Minor textual changes; scores remain in similar band (`overall` ~0.45–0.5).
  - 3rd refinement:
    - `...133505_refined_20251202_133536.*`
    - Refined template vs original is very close (extra clause about bird being unable to fly), but Gemini still scores it ~0.45 overall.

- **Qualitative observations**
  - Under Gemini’s scoring, the refiner makes only **small local edits**:
    - Slightly clarifying the problem (“unable to fly”).
    - Tiny shifts in phrasing; no large structural or thematic moves.
  - Gemini continues to view the story as:
    - Clear and age-appropriate,
    - Warm but **not meaningfully novel or deep**.
  - This suggests:
    - Our current refinement prompt is still too conservative to satisfy a very strict judge.
    - Gemini is useful as a **secondary filter** signalling “this is not yet special,” but not (yet) driving large creative leaps on its own.

### 2025-12-02 – Gemini 3 Pro as both generator and judge (The Little Lost Treasure)

- **Config**
  - Generator model: `google/gemini-3-pro-preview`.
  - Generator prompt: `G1_novel_innerChoice_showDontTell`.
  - Judge model: `google/gemini-3-pro-preview`.
  - Base template: `madlib_story_level3_20251202_133913.*` – *The Little Lost Treasure*.

- **Base story (Gemini-generated)**
  - Child `[slot_name]` finds a shiny small object in an outdoor place (`[slot_place]`).
  - Internally wants to keep it (“I will keep this treasure forever”) but notices a worried animal `[slot_animal]` searching.
  - Brief inner decision: looks at treasure, looks at sad animal, chooses to return it.
  - Animal does a happy movement `[slot_movement]` and shares a snack `[slot_snack]`; child feels good about sharing.
  - Slots include one slightly more abstract type (`slot_feeling`), but are still reasonably concrete for Mad Libs use.

- **3-step refinement under Gemini-only loop**
  - After 3 refinements:
    - Latest comparison file: `madlib_story_level3_20251202_133913_refined_20251202_134025_refined_20251202_134150_refined_20251202_134304.txt`.
    - Story remains essentially the same arc:
      - Hike/adventure → flash of color → lost object → worried animal → kind return → shared snack → goodbye.
    - Refinements polish:
      - Openings (“One afternoon, [name] went on an adventure…”).
      - Specificity (“fuzzy [slot_animal]”, “special treasure”).
      - Tone (“Here you go!” said kindly; “funny [slot_movement]”).
    - Gemini’s scores settle around:
      - `overall`: ~0.7,
      - High `story_arc`, `emotional_warmth`, `reading_level_fit`,
      - Moderate `curiosity_hooks` and `memorable_moment`,
      - Low–moderate `novelty` and `character_depth`.

- **Qualitative comparison to Mercury-generated stories**
  - The Gemini-generated template is **clean and morally clear**, with:
    - A sharp inner decision (keep vs return treasure).
    - Good age-appropriate tension, and strong warmth.
  - It is, however, still sitting in a familiar “lost treasure / small forest animal” pattern, similar in spirit to the better Mercury-based stories.
  - Over three refinements, Gemini improves phrasing and slightly deepens emotional cues, but:
    - Does not introduce a markedly more original twist or image.
    - Its own low `novelty` and `character_depth` scores reflect that it holds the bar high but still produces iterations inside a well-trodden template.

- **Process insight**
  - Gemini 3 Pro as both generator and judge yields **highly safe, structurally strong stories with clear inner choices**, but:
    - It doesn’t, on its own with current prompts, consistently push into “truly remarkable” territory.
    - Its strict judging is more valuable as a *check* than as the sole driver of refinement.
  - A promising hybrid strategy:
    - Use Mercury for fast, diverse generation and first-pass polish.
    - Use Gemini as a **second-pass critic** that:
      - Filters for higher `novelty` / `memorable_moment` / `character_depth`,
      - And perhaps triggers a separate, more adventurous refinement prompt when its scores are low.

### 2025-12-02 – Gemini 2.5 Flash vs Gemini 3 Pro as judges (latency, cost, quality)

- **Config**
  - Level: 3.
  - Generator: `inception/mercury` at higher temp (`generator_temperature = evolver_generator_temperature ≈ 1.3`).
  - Judge A (earlier runs): `google/gemini-3-pro-preview` at low temp (`judge_temperature = 0.1`).
  - Judge B (this run): `google/gemini-2.5-flash` at low temp (`judge_temperature = 0.1`).
  - All requests via OpenRouter with `usage: { include: true }` and new logging for latency.

- **Gemini 2.5 Flash run (judge) – key outputs**
  - Command:
    - `python madlibs_story_evolver.py --level 3 --model inception/mercury --judge-model google/gemini-2.5-flash --count 5`
  - Typical **generator (Mercury)** call:
    - Tokens: ~1.6k–2.1k total, cost ≈ $0.0011–$0.0015 per story.
    - Latency: ~3.1–4.3 s per story.
  - Typical **Gemini 2.5 Flash judge** call:
    - Tokens: ~1.7k–2.1k total, cost ≈ $0.00125–$0.00155 per judgment.
    - Latency: ~2.2–3.3 s per judgment (consistently snappy for this size).
  - Top candidates (by combined heuristic + Flash-judge score):
    - **The Lost Toy Adventure** (`...140358.*`)
      - Sentences: 10, Slots: 6, `judge_overall ≈ 0.80`, strong `story_arc` (≈0.90), `engagement` (≈0.80).
      - Arc: toy floats away like a bright cloud; child almost gives up but chooses to ask pet for help; pet follows a “rainbow trail” to a hidden pond; they recover the toy and share a snack.
      - Qualitative: clean arc plus a vivid center image (rainbow trail to pond), nicely aligned with our inner-decision + memorable-moment goals.
    - **The Glistening Ball and the Kind Rabbit** (`...140417.*`)
      - Sentences: 12, Slots: 7, `judge_overall ≈ 0.75`.
      - Arc: glowing ball that “glows like a firefly”, shy rabbit, child almost keeps ball but decides to give it to the rabbit, shared play and snack under a tree.
      - Qualitative: very on-brand for our values (kindness / sharing) with a strong, simple inner decision and a distinct glowing-ball image.

- **Qualitative comparison vs Gemini 3 Pro as judge**
  - **Strictness / scoring:**
    - Gemini 3 Pro tended to give **overall ≈ 0.45–0.55** to similar-quality stories (even when they felt quite polished), especially hammering on `novelty` and `character_depth`.
    - Gemini 2.5 Flash is **materially more generous** (`overall ≈ 0.65–0.80`) on these Mercury high-temp stories, especially when there is a clear inner decision and one standout image.
  - **Taste / signal:**
    - Both judges agree on what is “structurally sound and warm”, but:
      - Gemini 3 Pro is better at signaling “this is fine but not remarkable” and thus is a good *high-bar critic*.
      - Gemini 2.5 Flash feels like a **pragmatic, fast filter** that still meaningfully prefers stronger arcs/images over weaker ones, but without the same harshness on novelty.
  - **Latency and cost tradeoff:**
    - In practice, Gemini 2.5 Flash is **fast enough (≈3 s per judgment)** and **not obviously worse in outcome** for our current use (ranking Mercury populations).
    - Given that the **generator is already ~3–4 s per candidate**, Flash’s speed and cost profile make it a strong default for bulk offline library-building, while we reserve Gemini 3 Pro for spot-checks or small “elite” subsets when we really want a higher-taste critic.

- **Current leaning**
  - For *day-to-day DG population runs* (generating many candidates, ranking, picking seeds): **use Mercury + Gemini 2.5 Flash** for speed/cost.
  - For *meta-experiments and final curation* (small N, looking for truly standout stories): occasionally **re-score top candidates with Gemini 3 Pro** to sanity-check novelty / depth without paying its latency on every story.

### 2025-12-02 – Prompt variant: “no clichés + one twist” + kid retellability judge

- **Config**
  - Generator:
    - Model: `inception/mercury`.
    - Temperature: high (`generator_temperature ≈ 1.3`).
    - Prompt version: `G2_noCliche_oneTwist_innerChoice_showDontTell`.
    - New constraints:
      - Explicitly avoid centering the story on generic “lost balloon/kite + snack under tree” patterns **unless** there is a clearly unusual cozy element.
      - Require **exactly one** small, safe, slightly odd twist (e.g., humming toy, tree that remembers names, glowing kite when someone is kind).
  - Judge:
    - Model: `google/gemini-2.5-flash`.
    - Prompt: `J1_novelty_memorable_showDontTell_depth` + new `kid_retellability` axis:
      - “How easy for a 6–8 year old to retell the story in 2–3 sentences, naming the main character and one special thing that happened?”
  - Command:
    - `python madlibs_story_evolver.py --level 3 --model inception/mercury --judge-model google/gemini-2.5-flash --count 5`

- **Early results (run truncated by JSON quirk after 2.5 candidates, but top stories saved)**
  - **The Singing Kite Adventure** (`madlib_story_level3_20251202_141341.*`)
    - Sentences: 12, Slots: 8.
    - Arc: child + pet find a bright kite that **hums and glows** a warm color when the child laughs; child almost tosses the kite away but instead ties it to their backpack and heads to a playground activity; they share a snack while the kite sings a lullaby.
    - Qualitative:
      - Still in the kite motif, but now the kite has a very explicit, retellable twist (a humming, glowing kite), and the inner decision (toss vs keep-and-share) is clearer.
      - Feels easy to retell: “A kid finds a singing kite that glows when they laugh and decides to keep it and share it with their pet.”
  - **The Happy Toy and the Kind Friend** (`madlib_story_level3_20251202_141347.*`)
    - Sentences: 13, Slots: 7.
    - Arc: child and pet meet a sad, lonely toy; child considers leaving it alone but chooses to help; first tries song, then shares a snack; the toy starts to hum like a tiny drum and glows, lighting up the playground; they all play and go home happy.
    - Qualitative:
      - Moves away from “lost kite” and instead centers on a reactive toy with a specific behavior (humming/glowing drum‑toy).
      - Contains multiple micro-decisions and a strong centerpiece moment (“toy hums and lights up the playground”), very retellable.

- **Prompt-level takeaways**
  - The **“no clichés + one twist”** constraints successfully steer Mercury toward:
    - Keeping the comforting structure (small problem → choice → cozy end),
    - But consistently attaching a **distinctive magical-but-soft property** (singing kite, humming/glowing toy) that a kid can name later.
  - Adding **`kid_retellability`** to the judge rubric appears to align with our own instincts:
    - Stories with a single, clear “hook sentence” (singing kite; humming toy that lights the playground) rise to the top.
  - Remaining gap:
    - Motifs are still fairly close to our existing comfort zone (kites, toys, playgrounds); next variants could push on **setting diversity** (e.g., kitchen, bedtime, bus ride) while preserving the new twist + retellability constraints.
