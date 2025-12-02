## Mad Libs Darwin/Goedel Experiment – Index & Notes

**Purpose**: Track and organize the experiments we ran to evolve high-quality, Level 3 Mad Libs–style story templates using generation, heuristic scoring, LLM-based judging, and iterative refinement.

### 1. Key Python tools

- **`genai/madlibs_story_generator.py`**
  - Generates a single Mad Libs story template for a given `--level` and `--model`.
  - Uses a structured JSON schema with `slots` (blanks) and `sentences` (`text_with_blanks` + `slot_ids`).
  - Outputs:
    - JSON template: `genai/generated_madlibs_stories/madlib_story_level3_YYYYMMDD_HHMMSS.json`
    - Human-readable TXT: `..._YYYYMMDD_HHMMSS.txt`

- **`genai/madlibs_story_evolver.py`**
  - Generates a **population** of templates and scores them.
  - Inputs:
    - `--level` (e.g. 3),
    - `--model` (e.g. `inception/mercury` for generation),
    - optional `--judge-model` (LLM used as story judge).
  - For each candidate:
    - Saves JSON/TXT via `_save_template(...)` (same directory as above).
    - Computes:
      - Heuristic score (sentence count, slot quality, blank density).
      - Optional LLM-judge scores (`overall`, `story_arc`, `character_engagement`, etc.).
    - Prints a ranked summary (best to worst) to the terminal.

- **`genai/madlibs_story_refiner.py`**
  - Refines a **single** existing template using an LLM.
  - Input:
    - `--input` path to a JSON template.
    - `--model` (refiner).
    - `--judge-model` (LLM judge, can be same as `--model`).
  - Behavior:
    - Loads the original or (if present) the `refined` sub-object from previous comparison JSON.
    - Asks the refiner to improve arc/engagement/curiosity while preserving reading level and slot structure.
    - Calls the same judge used in `madlibs_story_evolver.py`.
    - Saves a side-by-side comparison:
      - `*_refined_YYYYMMDD_HHMMSS.json` – contains `original`, `refined`, and `judge_scores`.
      - `*_refined_YYYYMMDD_HHMMSS.txt` – human-readable diff (original vs refined sentences, judge scores).

### 2. Generated story templates – Level 3

All stored under: `genai/generated_madlibs_stories/`

**Early experiments (no LLM judge or heuristic-only scoring):**

- `madlib_story_level3_20251202_112955.*`
- `madlib_story_level3_20251202_113435.*`
- `madlib_story_level3_20251202_113458.*`

**Population / evolver runs (with heuristic scoring, then LLM judge):**

- `madlib_story_level3_20251202_114012.*` – population candidate
- `madlib_story_level3_20251202_114016.*` – population candidate
- `madlib_story_level3_20251202_114019.*` – **Milo's Missing Balloon**
- `madlib_story_level3_20251202_114022.*` – population candidate
- `madlib_story_level3_20251202_115947.*` – population candidate
- `madlib_story_level3_20251202_115950.*` – **A Playful Day in the Park**
- `madlib_story_level3_20251202_115954.*` – population candidate

**Later generator calls (fresh seeds used for refinement):**

- `madlib_story_level3_20251202_122540.*` – **Mia and the Lost Kite** (base template)

### 3. Refinement chains (per story)

#### 3.1 A Playful Day in the Park

Base template:
- `madlib_story_level3_20251202_115950.json`
- `madlib_story_level3_20251202_115950.txt`

Refinement / comparison files:
- First refinement:
  - `madlib_story_level3_20251202_115950_refined_20251202_121002.json`
  - `madlib_story_level3_20251202_115950_refined_20251202_121002.txt`
- Second refinement (jumped to “The Curious Day at the Playground” variant):
  - `madlib_story_level3_20251202_115950_refined_20251202_121002_refined_20251202_121947.json`
  - `madlib_story_level3_20251202_115950_refined_20251202_121002_refined_20251202_121947.txt`

Notes:
- The first refinement preserved the park story and slightly enriched imagery and emotional beats.
- The second refinement produced a side-step variant (playground/kite-sharing) with similar judge scores, suggesting diminishing returns for this story under the current prompts.

#### 3.2 Mia and the Lost Kite

Base template:
- `madlib_story_level3_20251202_122540.json`
- `madlib_story_level3_20251202_122540.txt`

Refinement / comparison chain:
- First refinement:
  - `madlib_story_level3_20251202_122540_refined_20251202_122554.json`
  - `madlib_story_level3_20251202_122540_refined_20251202_122554.txt`
- Second refinement:
  - `madlib_story_level3_20251202_122540_refined_20251202_122554_refined_20251202_122942.json`
  - `madlib_story_level3_20251202_122540_refined_20251202_122554_refined_20251202_122942.txt`
- Third refinement:
  - `madlib_story_level3_20251202_122540_refined_20251202_122554_refined_20251202_122942_refined_20251202_122951.json`
  - `madlib_story_level3_20251202_122540_refined_20251202_122554_refined_20251202_122942_refined_20251202_122951.txt`
- Fourth refinement:
  - `madlib_story_level3_20251202_122540_refined_20251202_122554_refined_20251202_122942_refined_20251202_122951_refined_20251202_123003.json`
  - `madlib_story_level3_20251202_122540_refined_20251202_122554_refined_20251202_122942_refined_20251202_122951_refined_20251202_123003.txt`

Notes:
- This chain is a good example of iterative improvement:
  - First refinement clarifies the lost-kite arc and emotional beat (sadness → search → success → shared snack).
  - Later refinements add richer search sequences (multiple trees, vantage points) and a clearer sense of teamwork and friendship.
  - Judge `overall` scores peak around ~0.92, with high `story_arc`, `emotional_warmth`, and `madlibs_usability`, then flatten (diminishing returns).

### 4. How to replicate / extend experiments

**Generate a new Level 3 template:**

```bash
cd genai
python madlibs_story_generator.py --level 3 --model inception/mercury
```

**Run a population + judge ranking:**

```bash
cd genai
python madlibs_story_evolver.py \
  --level 3 \
  --model inception/mercury \
  --judge-model inception/mercury \
  --count 5
```

**Refine an existing template N times:**

Repeat:

```bash
cd genai
python madlibs_story_refiner.py \
  --input generated_madlibs_stories/<base_or_comparison>.json \
  --model inception/mercury \
  --judge-model inception/mercury
```

Each run creates `*_refined_YYYYMMDD_HHMMSS.{json,txt}` that nests the latest `refined` template, so feeding comparison JSONs back into the refiner lets you build a chain:

> base → refined_1 → refined_2 → refined_3 …

### 5. Future meta-Darwin/Goedel experiments

For future iterations on the *process itself*, we can:

- Add **named generator prompt variants** (e.g. `G_showDontTell`, `G_novelImage`, `G_innerChoice`).
- Add **judge variants** that weight:
  - `novelty`, `memorable_moment`, `show_vs_tell`, `character_depth`.
- For each `(story, generator_variant, judge_variant, model)`:
  - Run N refinements and archive the chain in this same directory, with:
    - Clear naming or a small JSON index mapping `story_id` → `config` → files.

This document serves as the entry point and high-level map for all Mad Libs Darwin/Goedel experiments so far, so we can quickly locate:

- Which stories we evaluated,
- How many refinement rounds were run,
- And where to read the side-by-side comparisons.


