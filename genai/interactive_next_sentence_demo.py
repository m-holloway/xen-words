"""
Minimal interactive next-sentence demo against OpenRouter, without FastAPI,
Pydantic, or the `openai` Python client (to avoid wheel build issues).

This is a self-contained CLI script so you can *feel* the one-sentence-at-a-time
mechanic quickly.

Usage (from repo root):
    cd genai
    python interactive_next_sentence_demo.py
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List

from datetime import datetime
import random

import urllib.request
import urllib.error


@dataclass
class ValuesGoals:
    core_values: List[str]
    skill_focus: List[str]
    tone_preferences: Dict[str, str]
    content_boundaries: Dict[str, List[str]]
    family_context_notes: str = ""


def load_env() -> Dict[str, str]:
    """
    Minimal .env loader, mirroring the pattern in `test_story_simple.py`.
    Looks for a `.env` file in the same `genai` directory.
    """
    env_file = Path(__file__).parent / ".env"
    env_vars: Dict[str, str] = {}
    if env_file.exists():
        with env_file.open() as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                # Strip inline comments and surrounding whitespace on the value
                value = value.split("#", 1)[0].strip()
                if key:
                    env_vars[key] = value
    return env_vars


def _system_prompt() -> str:
    return (
        "You are a highly attuned children's story co-author helping a parent and child "
        "write a story one sentence at a time.\n\n"
        "Your job in this mode is very specific:\n"
        "- Read the JSON input that describes the story context, values/goals, current beat, "
        "  and what the child just said or chose.\n"
        "- Propose a SMALL SET of candidate next sentences (each ONE sentence long) that:\n"
        "  * Each candidate is an INDEPENDENT alternative for the SAME next line.\n"
        "    They must NOT depend on, continue, or reference each other.\n"
        "    If the user chooses candidate 2, it should still work as the immediate\n"
        "    next line even if candidate 1 is never used.\n"
        "  * The JSON input includes `child_event.utterance_text` (the last line) and\n"
        "    a boolean `last_line_is_fragment`.\n"
        "    - If `last_line_is_fragment` is true (e.g., the last line ends with '...'\n"
        "      or sets up a phrase like 'Its name was...'), treat your `sentence` as a\n"
        "      DIRECT continuation that, when appended, makes a single natural sentence.\n"
        "      Do not repeat the same setup (e.g., do NOT write 'Its name was Twinkle'\n"
        "      after 'Its name was...' — instead write 'Twinkle, and it sparkled with all\n"
        "      the colors of the rainbow.').\n"
        "    - If `last_line_is_fragment` is false, your `sentence` should be a complete\n"
        "      next line on its own.\n"
        "  * The JSON input also includes `pacing.story_step` and\n"
        "    `pacing.target_sentence_count`.\n"
        "    - In the early part of the story (first third of target sentences), focus on\n"
        "      introducing characters, setting, and a gentle sense of curiosity.\n"
        "    - In the middle third, deepen the situation or small challenge, but do not\n"
        "      endlessly add new characters or magical objects.\n"
        "    - In the final third (when `story_step` is close to\n"
        "      `target_sentence_count`), gently move toward closure:\n"
        "        • resolve at least one open question or tension,\n"
        "        • bring emotional payoff (relief, joy, pride),\n"
        "        • avoid opening brand-new plot threads.\n"
        "    - It's okay for the story to end softly and satisfyingly at or near the\n"
        "      target sentence count; do not always assume the story must keep going\n"
        "      forever.\n"
        "  * Build directly on the child's idea and the current story context.\n"
        "  * Match the current beat goal and target tension.\n"
        "  * Align with the family's values and content boundaries.\n"
        "  * Fit the reading level while keeping language vivid and joyful.\n"
        "    The JSON includes `reading_level` (1–5) and a `reading_band` descriptor.\n"
        "    Treat these as firm constraints on sentence length and complexity:\n"
        "      - Level 1 (Emerging Reader): child is just decoding. ONE very short\n"
        "        sentence (about 4–8 words). Almost all words should be high‑frequency\n"
        "        sight words or simple CVC/CVCC words. Avoid long adjectives,\n"
        "        multi‑clause sentences, or rare vocabulary.\n"
        "      - Level 2 (Developing Reader): still simple. 1 short sentence (or very\n"
        "        occasionally 2). Mostly high‑frequency words with a few gently new\n"
        "        words; very simple dialogue tags are okay.\n"
        "      - Level 3 (Transitional Reader): can handle a bit more length and\n"
        "        description. 1–2 sentences are acceptable. A few tier‑two words and\n"
        "        simple clauses are fine.\n"
        "      - Level 4 (Fluent Reader): longer sentences with clauses are fine;\n"
        "        more precise vocabulary as long as context makes meaning clear.\n"
        "      - Level 5 (Confident Reader): multi‑clause sentences, figurative\n"
        "        language, and more complex themes are welcome.\n"
        "  * Variety and freshness: avoid overusing the same kind of protagonist or\n"
        "    creature (for example, do NOT keep introducing turtles unless one is\n"
        "    already clearly part of this specific story). Let the spark, setting, and\n"
        "    prior lines guide who or what appears next.\n"
        "- For each candidate, you will also SELF-SCORE how well it meets these criteria.\n\n"
        "Important constraints:\n"
        "- Do not contradict what already happened.\n"
        "- Do not introduce dark, violent, or disturbing content.\n"
        "- Keep emotional challenge gentle; resolve scary elements with warmth.\n"
        "- Always respond with VALID JSON ONLY. No markdown fences, no extra commentary.\n\n"
        "Output format (strict JSON):\n"
        "{\n"
        '  "candidates": [\n'
        "    {\n"
        '      "id": "cand_1",\n'
        '      "sentence": "One clear, read-aloud-friendly sentence.",\n'
        '      "scores": {\n'
        '        "values_alignment": 0.0,\n'
        '        "tension": 0.0,\n'
        '        "reading_level_fit": 0.0,\n'
        '        "novelty": 0.0,\n'
        '        "coherence_with_plan": 0.0\n'
        "      },\n"
        '      "rationale": {\n'
        '        "values_alignment": "Short natural-language reason.",\n'
        '        "reading_level_fit": "Short natural-language reason."\n'
        "      },\n"
        '      "tags": ["short", "list", "of", "descriptive", "tags"]\n'
        "    }\n"
        "  ],\n"
        '  "suggested_beat_transition": {\n'
        '    "stay_on_beat": true,\n'
        '    "reason": "Why we should stay on this beat or move to the next."\n'
        "  }\n"
        "}\n"
    )


def _build_payload(
    *,
    num_candidates: int,
    story_so_far: List[str],
    child_line: str,
    guidance: str | None,
    reading_level: int,
    reading_band: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Build the JSON payload for the next-sentence request.

    - `story_so_far` is the list of sentences already chosen.
    - `child_line` is the most recent line the user added (seed for this turn).
    - `reading_level`/`reading_band` mirror the Flutter app's reading level bands (1–5).
    """
    values = ValuesGoals(
        core_values=["kindness", "courage", "curiosity"],
        skill_focus=["trying_new_things", "asking_for_help"],
        tone_preferences={"humor": "gentle", "tension": "low", "pace": "cozy"},
        content_boundaries={
            "avoid": ["bullying", "realistic injury", "death of family members"],
            "soften": ["monsters", "storms"],
        },
        family_context_notes=(
            "Child sometimes worries about new situations; keep things cozy and safe. "
            "They enjoy many kinds of characters and creatures; do not default to the "
            "same animal or hero type in every story."
        ),
    )

    # Build a lightweight textual context from the running story.
    if story_so_far:
        narrator_text = "\n".join(story_so_far)
    else:
        narrator_text = "It was a soft, cloudy evening by the pond."

    effective_child_line = child_line or "The turtle finds a glowing rock."

    # Very simple pacing signal: how far into the story we are and roughly
    # where we aim to land for a single-session arc.
    story_step = len(story_so_far) + 1
    target_sentence_count = 12  # soft target; model can overshoot a bit.

    def _is_fragment(line: str) -> bool:
        s = line.strip()
        if not s:
            return False
        # Treat lines ending with "..." or containing blanks as fragments.
        if s.endswith("...") or "____" in s:
            return True
        # Heuristic: if it doesn't end with sentence punctuation, consider it fragment-like.
        if s[-1] not in ".?!":
            return True
        return False

    return {
        "context": {
            "story_id": "demo_story",
            "plan_id": "plan_1",
            "profile_id": "child_1",
            "reading_level": reading_level,
            "reading_band": reading_band,
            "parent_prompt": (
                "A cozy adventure that grows into something magical and meaningful, "
                "with characters that fit the world of this particular story."
            ),
            "child_context": (
                "Loves imaginative worlds, animals, robots, and space; sometimes worried "
                "about new things but very curious. Avoid always choosing the same kind "
                "of main character (like turtles) unless the story already established it."
            ),
            "cast_context": None,
            "values_goals": asdict(values),
            "exemplar_snippets": [
                {
                    "text": "The moon peeked between the clouds like a shy friend playing hide-and-seek.",
                    "child_rating": 5,
                }
            ],
        },
        "current_beat": {
            "id": "beat_1",
            "goal": "Introduce protagonist and a small, curious moment.",
            "tension_target": 0.2,
            "values_tags": ["curiosity", "warmth"],
        },
        "pacing": {
            "story_step": story_step,
            "target_sentence_count": target_sentence_count,
        },
        "recent_turns": [
            {
                "speaker": "narrator",
                "text": narrator_text,
            },
            {
                "speaker": "child",
                "text": effective_child_line,
            },
        ],
        "child_event": {
            "utterance_text": effective_child_line,
            "choice_id": None,
        },
        "last_line_is_fragment": _is_fragment(effective_child_line),
        "user_guidance": guidance,
        "num_candidates": num_candidates,
    }


def _strip_markdown_fences(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        t = t.lstrip("`")
        if t.lower().startswith("json"):
            t = t[4:]
        if "```" in t:
            t = t.split("```", 1)[0]
    return t.strip()


def _extract_first_json_object(text: str) -> str:
    """
    Extract the first JSON object from a string that may contain extra
    commentary before or after the JSON.
    """
    stripped = _strip_markdown_fences(text)
    start = stripped.find("{")
    end = stripped.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise json.JSONDecodeError("No JSON object found", stripped, 0)
    return stripped[start : end + 1]


def _parse_model_output(text: str) -> Dict[str, Any]:
    """
    Parse the model output into a dict.

    Strategy:
    1. Try to extract the first full JSON object and parse it.
    2. If that fails, fall back to extracting just the `candidates` array
       and wrap it in a minimal object. This handles slightly malformed
       outputs where extra keys trail after the array.
    """
    stripped = _strip_markdown_fences(text)

    # Attempt full-object parse first.
    try:
        extracted = _extract_first_json_object(stripped)
        return json.loads(extracted)
    except json.JSONDecodeError:
        pass

    # Fallback: find the candidates array.
    key_idx = stripped.find('"candidates"')
    if key_idx == -1:
        raise json.JSONDecodeError("No `candidates` key found", stripped, 0)

    bracket_idx = stripped.find("[", key_idx)
    if bracket_idx == -1:
        raise json.JSONDecodeError("No `[` after `candidates` key", stripped, key_idx)

    depth = 0
    end_idx = None
    for i in range(bracket_idx, len(stripped)):
        ch = stripped[i]
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                end_idx = i
                break

    if end_idx is None:
        raise json.JSONDecodeError("Unterminated candidates array", stripped, bracket_idx)

    array_str = stripped[bracket_idx : end_idx + 1]
    try:
        candidates = json.loads(array_str)
    except json.JSONDecodeError as e:
        raise json.JSONDecodeError(
            f"Failed to parse candidates array only: {e.msg}", array_str, e.pos
        )

    return {
        "candidates": candidates,
        "suggested_beat_transition": {},
    }


def _suggest_blank_fills(
    fragment: str,
    api_key: str,
    model: str,
) -> List[str]:
    """
    Ask the model for short, child-friendly completions to fill a single blank
    (represented by '_____') in a starting fragment.

    Returns up to 4 fill strings, or an empty list on failure.
    """
    system = (
        "You help design fun, child-friendly completions for a single blank in a "
        "story opening fragment. The blank is represented by '_____'.\n\n"
        "Constraints:\n"
        "- 1–3 words per fill\n"
        "- Age-appropriate for 4–8 year olds\n"
        "- Warm, imaginative, non-scary\n"
        "- Avoid brand names and real people\n"
        "- Each fill should plug directly into the blank and read naturally.\n"
        "Output JSON only, no commentary."
    )

    user = {
        "fragment": fragment,
        "instructions": (
            "Propose about 4 diverse options that could fill the blank. "
            "Return JSON:\n"
            "{\n"
            '  "fills": [\n'
            '    "curious turtle",\n'
            '    "kind robot",\n'
            '    \"tiny dragon\", \n'
            '    \"glittery cloud\"\n'
            "  ]\n"
            "}\n"
        ),
    }

    body = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": system,
                "cache_control": {"type": "ephemeral"},
            },
            {
                "role": "user",
                "content": json.dumps(user, ensure_ascii=False),
                "cache_control": {"type": "ephemeral"},
            },
        ],
        "temperature": 0.9,
        "max_output_tokens": 512,
        "usage": {"include": True},
    }

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Blank Fill Suggester",
    }

    data_bytes = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", method="POST"
    )
    for k, v in headers.items():
        req.add_header(k, v)
    req.data = data_bytes

    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            raw = response.read().decode("utf-8")
            data = json.loads(raw)
    except Exception:
        return []

    content = data["choices"][0]["message"]["content"]
    text = _strip_markdown_fences(str(content or ""))
    try:
        extracted = _extract_first_json_object(text)
        parsed = json.loads(extracted)
    except json.JSONDecodeError:
        return []

    fills = parsed.get("fills") or []
    return [str(f).strip() for f in fills if str(f).strip()]


def _save_story(
    story: List[str],
    model: str,
    model_source: str,
    turns: List[Dict[str, Any]],
) -> None:
    """Persist the final story and turn log to timestamped files for later review."""
    if not story:
        return

    out_dir = Path(__file__).parent / "interactive_stories"
    out_dir.mkdir(parents=True, exist_ok=True)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Human-readable text file
    txt_path = out_dir / f"interactive_story_{ts}.txt"
    with txt_path.open("w", encoding="utf-8") as f:
        f.write(f"Model: {model} (source={model_source})\n")
        f.write(f"Created at: {datetime.now().isoformat()}\n\n")
        for i, line in enumerate(story, 1):
            f.write(f"{i}. {line}\n")

        if turns:
            f.write("\n\n=== Turn log ===\n")
            for t in turns:
                f.write(f"\nStep {t.get('step')}, action={t.get('action')}\n")
                if t.get("user_guidance"):
                    f.write(f"  guidance: {t['user_guidance']}\n")
                f.write("  candidates:\n")
                for idx, s in enumerate(t.get("candidates") or [], 1):
                    f.write(f"    {idx}) {s}\n")
                if t.get("chosen_sentence"):
                    f.write(f"  chosen: {t['chosen_sentence']}\n")

    # Structured JSON file for programmatic inspection / rewind features
    json_path = out_dir / f"interactive_story_{ts}.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "model": model,
                "model_source": model_source,
                "created_at": datetime.now().isoformat(),
                "story": story,
                "turns": turns,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    print(f"\nStory saved to: {txt_path}")
    print(f"Turn log saved to: {json_path}")


def main() -> None:
    # Load .env using the same pattern as other genai scripts
    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env")

    # Resolve model with clear precedence, and log which one we used
    model_source = None
    if env.get("STORY_BUILDER_BY_SENTENCE_MODEL"):
        model = env["STORY_BUILDER_BY_SENTENCE_MODEL"]
        model_source = "STORY_BUILDER_BY_SENTENCE_MODEL"
    elif env.get("INTERACTIVE_STORY_MODEL"):
        model = env["INTERACTIVE_STORY_MODEL"]
        model_source = "INTERACTIVE_STORY_MODEL"
    else:
        # Hardcoded fallback when no story-builder-specific override is present.
        # Default to Qwen 3 Next 80B instruct on OpenRouter.
        model = "qwen/qwen3-next-80b-a3b-instruct"
        model_source = "hardcoded fallback (qwen/qwen3-next-80b-a3b-instruct)"

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        # Header values must be latin-1 encodable; use a simple ASCII title.
        "X-Title": "Xen Words - Interactive Story Demo",
    }

    story: List[str] = []
    turn_logs: List[Dict[str, Any]] = []
    guidance: str | None = None
    tuning_tokens: Dict[str, int] = {"crazy": 0, "challenge": 0, "cozy": 0}

    usage_totals: Dict[str, Any] = {
        "requests": 0,
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
        "prompt_cache_read_tokens": 0,
        "prompt_cache_write_tokens": 0,
        "cache_discounts": [],
    }

    # Reading level selection (mirrors Flutter app's 1–5 bands)
    reading_bands: Dict[int, Dict[str, Any]] = {
        1: {
            "level": 1,
            "label": "Level 1 • Emerging Reader",
            "grade_band": "Late Pre-K to Kindergarten",
            "lexile_band": "BR to 150L",
            "description": (
                "Decodable text with heavy picture support and repeated sight-word "
                "patterns; 1 short sentence per page."
            ),
        },
        2: {
            "level": 2,
            "label": "Level 2 • Developing Reader",
            "grade_band": "Kindergarten to Early Grade 1",
            "lexile_band": "150L – 300L",
            "description": (
                "2–4 short sentences; simple story arc with basic dialogue tags; "
                "introduces consonant blends and two-syllable words."
            ),
        },
        3: {
            "level": 3,
            "label": "Level 3 • Transitional Reader",
            "grade_band": "Grades 1–2",
            "lexile_band": "300L – 500L",
            "description": (
                "Paragraphs of 3–5 sentences, richer dialogue and description, "
                "mixture of familiar and tier-two vocabulary."
            ),
        },
        4: {
            "level": 4,
            "label": "Level 4 • Fluent Reader",
            "grade_band": "Grades 2–3",
            "lexile_band": "500L – 650L",
            "description": (
                "Fuller sentences with clauses; more precise vocabulary explained "
                "in context; themes of problem solving and growth mindset."
            ),
        },
        5: {
            "level": 5,
            "label": "Level 5 • Confident Reader",
            "grade_band": "Grades 3–4",
            "lexile_band": "650L – 750L",
            "description": (
                "Multi-clause sentences, figurative language, and higher-concept "
                "themes; comparable to early chapter books."
            ),
        },
    }

    print("\n=== Interactive Story Builder (one sentence at a time) ===")
    print("\nChoose a reading level for this session (1–5):")
    for lvl in range(1, 6):
        band = reading_bands[lvl]
        print(f"  {lvl}) {band['label']} — {band['grade_band']}")
    raw_level = input("Enter level 1–5 (default 2): ").strip()
    try:
        reading_level = int(raw_level) if raw_level else 2
    except ValueError:
        reading_level = 2
    if reading_level < 1 or reading_level > 5:
        reading_level = 2
    reading_band = reading_bands[reading_level]
    print(
        f"Using reading level {reading_level}: {reading_band['label']} "
        f"({reading_band['grade_band']})"
    )

    # Try to load starting fragments generated by generate_story_fragments.py
    fragments_path = Path(__file__).parent / "story_fragments.json"
    fragments: List[str] = []
    if fragments_path.exists():
        try:
            with fragments_path.open("r", encoding="utf-8") as f:
                data = json.load(f)
            raw_frags = data.get("fragments") or []
            fragments = [str(x).strip() for x in raw_frags if str(x).strip()]
        except Exception:
            fragments = []

    if fragments:
        # Offer two random "story sparks" to choose from, with ability to regenerate.
        while True:
            picks = random.sample(fragments, k=min(2, len(fragments)))
            print("\nChoose a starting story spark:")
            print(f"  A) {picks[0]}")
            if len(picks) > 1:
                print(f"  B) {picks[1]}")
            print("  C) Write my own opening line")
            print("  D) Show two different sparks")

            start_choice = input(
                "Choose A/B, C to write your own, or D to reshuffle: "
            ).strip().upper()
            if start_choice == "A":
                base_opening = picks[0]
                break
            elif start_choice == "B" and len(picks) > 1:
                base_opening = picks[1]
                break
            elif start_choice == "C":
                custom = input("Type your opening line: ").strip()
                base_opening = custom or "Once upon a time, there was a really really _____."
                break
            elif start_choice == "D":
                # Loop again with a fresh pair.
                continue
            else:
                print("Invalid choice, please try again.")

        # If the fragment contains a blank, we can either suggest fills or let the user type one.
        if "____" in base_opening:
            print(
                "\nThis spark has a blank. You can:\n"
                "  A) See 4 suggested ways to fill it\n"
                "  B) Type your own fill\n"
                "  C) Keep the blank as-is"
            )
            mode = input("Choose A/B/C: ").strip().upper()
            if mode == "A":
                fills = _suggest_blank_fills(base_opening, api_key, model)
                if fills:
                    fills = fills[:4]
                    print("\nSuggested fills:")
                    label_map = {}
                    for idx, fill in enumerate(fills):
                        label = chr(ord("A") + idx)
                        print(f"  {label}) {fill}")
                        label_map[label] = fill
                    print("  E) Type my own")
                    print("  F) Keep blank")
                    choice = input("Choose a fill (A-D), or E/F: ").strip().upper()
                    if choice in label_map:
                        chosen_fill = label_map[choice]
                        base_opening = (
                            base_opening.replace("_____", chosen_fill).replace("____", chosen_fill)
                        )
                    elif choice == "E":
                        manual = input(
                            "Type your fill (e.g., 'curious turtle', 'kind robot'): "
                        ).strip()
                        if manual:
                            base_opening = (
                                base_opening.replace("_____", manual).replace("____", manual)
                            )
                    # If F or anything else, leave the blank as-is.
                else:
                    # Fallback to manual if suggestions fail.
                    manual = input(
                        "Type your fill (e.g., 'curious turtle', 'kind robot'), "
                        "or press Enter to keep it as-is: "
                    ).strip()
                    if manual:
                        base_opening = (
                            base_opening.replace("_____", manual).replace("____", manual)
                        )
            elif mode == "B":
                manual = input(
                    "Type your fill (e.g., 'curious turtle', 'kind robot'), "
                    "or press Enter to keep it as-is: "
                ).strip()
                if manual:
                    base_opening = (
                        base_opening.replace("_____", manual).replace("____", manual)
                    )
            # mode C keeps the blank as-is.
    else:
        # Fallback to simple manual opening if no fragments are available.
        base_opening = input(
            "Enter your opening line (or press Enter to start with the default): "
        ).strip() or "The turtle finds a glowing rock."

    # Simple one-time "token" tuning for the session.
    print(
        "\nOptional: You have 3 'story tokens' to set the vibe "
        "(crazy, challenge, cozy)."
    )
    raw_tokens = input(
        "Enter crazy,challenge,cozy as e.g. 2,1,0 (or press Enter to skip): "
    ).strip()
    if raw_tokens:
        parts = [p.strip() for p in raw_tokens.replace(" ", "").split(",") if p.strip()]
        if len(parts) == 3:
            try:
                c1, c2, c3 = (max(0, int(x)) for x in parts)
                total = c1 + c2 + c3
                if total > 3:
                    scale = 3 / total
                    c1 = int(round(c1 * scale))
                    c2 = int(round(c2 * scale))
                    c3 = int(round(c3 * scale))
                tuning_tokens = {"crazy": c1, "challenge": c2, "cozy": c3}
            except ValueError:
                pass

    print(
        f"Tuning tokens set to: crazy={tuning_tokens['crazy']}, "
        f"challenge={tuning_tokens['challenge']}, cozy={tuning_tokens['cozy']}"
    )

    last_line = base_opening
    story.append(base_opening)

    try:
        while True:
            # Guidance applies to a single generation; consume and then clear it.
            guidance_to_use = guidance
            guidance = None

            payload = _build_payload(
                num_candidates=2,
                story_so_far=story,
                child_line=last_line,
                guidance=guidance_to_use,
                reading_level=reading_level,
                reading_band=reading_band,
            )
            payload["tuning_tokens"] = tuning_tokens

            body = {
                "model": model,
                "messages": [
                    {
                        "role": "system",
                        "content": _system_prompt(),
                        "cache_control": {"type": "ephemeral"},
                    },
                    {
                        "role": "user",
                        "content": json.dumps(payload, ensure_ascii=False),
                        "cache_control": {"type": "ephemeral"},
                    },
                ],
                "temperature": 0.85,
                "max_output_tokens": 512,
                "usage": {"include": True},
                "user": "story_builder_cli_demo",
            }

            print(
                f"\nCalling OpenRouter model={model} for next-sentence candidates "
                f"(source={model_source})..."
            )
            data_bytes = json.dumps(body).encode("utf-8")
            req = urllib.request.Request(
                "https://openrouter.ai/api/v1/chat/completions", method="POST"
            )
            # Use add_header to avoid any implicit latin-1 encoding issues
            for k, v in headers.items():
                req.add_header(k, v)
            req.data = data_bytes

            try:
                with urllib.request.urlopen(req, timeout=60) as response:
                    data = json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                error_body = e.read().decode("utf-8")
                print(f"\nOpenRouter API error {e.code}: {error_body}")
                break
            except Exception as e:
                print(f"\nRequest failed: {e}")
                break

            # Optional: print usage info so you can see cached vs uncached tokens
            usage = data.get("usage")
            if usage:
                print(f"Usage: {usage}")
                usage_totals["requests"] += 1
                for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
                    if isinstance(usage.get(key), (int, float)):
                        usage_totals[key] += usage[key]
                for key in ("prompt_cache_read_tokens", "prompt_cache_write_tokens"):
                    if isinstance(usage.get(key), (int, float)):
                        usage_totals[key] += usage[key]
                if isinstance(usage.get("cache_discount"), (int, float, float)):
                    usage_totals["cache_discounts"].append(usage["cache_discount"])

            content = data["choices"][0]["message"]["content"]
            text = str(content or "")
            try:
                parsed = _parse_model_output(text)
            except json.JSONDecodeError:
                print(
                    "\nModel did not return usable JSON; raw output (first 800 chars):"
                )
                print(text[:800])
                break

            raw_candidates = parsed.get("candidates") or []
            candidates = raw_candidates[:2]
            if not candidates:
                print("\nNo candidates returned; stopping.")
                break

            # Display recent story context (last 5 sentences)
            if story:
                print("\nRecent story (last 5 sentences):")
                window = story[-5:]
                # Show ellipsis if there is earlier context
                if len(story) > 5:
                    print("  ...")
                for i, line in enumerate(window, len(story) - len(window) + 1):
                    print(f"  {i}. {line}")
            else:
                print("\nStarting a new story...")

            # Show choices (A/B) + Write-in + Regenerate + Quit
            print("\nNext sentence options:")
            labels = ["A", "B"]
            available: List[tuple[str, str]] = []
            for label, cand in zip(labels, candidates):
                sent = (cand.get("sentence") or "").strip()
                print(f"  {label}) {sent}")
                available.append((label, sent))

            print("  C) Write my own sentence")
            print("  D) Regenerate new suggestions")
            print("  Q) Quit")

            # Flatten candidate sentences for logging
            cand_sentences = [(c.get("sentence") or "").strip() for c in candidates]

            choice = input(
                "Choose A/B, C to write your own, D to regenerate, or Q to quit: "
            ).strip().upper()
            if choice == "Q":
                # Log a terminal no-choice turn for completeness
                turn_logs.append(
                    {
                        "step": len(story) + 1,
                        "action": "quit",
                        "candidates": cand_sentences,
                        "chosen_sentence": None,
                        "user_guidance": None,
                    }
                )
                break
            elif choice == "C":
                custom = input("Type your sentence: ").strip()
                if not custom:
                    print("Empty sentence; skipping.")
                    continue
                chosen = custom
                turn_logs.append(
                    {
                        "step": len(story) + 1,
                        "action": "write_in",
                        "candidates": cand_sentences,
                        "chosen_sentence": chosen,
                        "user_guidance": None,
                    }
                )
            elif choice == "D":
                # Regenerate new suggestions without changing the story.
                guidance_input = input(
                    "Type a question or hint for the next line "
                    "(or press Enter for no extra guidance): "
                ).strip()
                guidance = guidance_input or None
                turn_logs.append(
                    {
                        "step": len(story) + 1,
                        "action": "regenerate",
                        "candidates": cand_sentences,
                        "chosen_sentence": None,
                        "user_guidance": guidance,
                    }
                )
                print("Regenerating suggestions...")
                continue
            else:
                mapping = {label: sent for label, sent in available}
                if choice not in mapping:
                    print("Invalid choice; please try again.")
                    continue
                chosen = mapping[choice]
                turn_logs.append(
                    {
                        "step": len(story) + 1,
                        "action": "choose_model_sentence",
                        "choice_label": choice,
                        "candidates": cand_sentences,
                        "chosen_sentence": chosen,
                        "user_guidance": None,
                    }
                )

            story.append(chosen)
            last_line = chosen

        # Final story printout
        if story:
            print("\n=== Final story ===")
            for i, line in enumerate(story, 1):
                print(f"  {i}. {line}")
            _save_story(story, model, model_source or "unknown", turn_logs)

            # Session-level usage summary
            print("\n=== Session usage summary (as reported by provider) ===")
            print(f"Requests: {usage_totals['requests']}")
            print(
                f"Prompt tokens: {usage_totals['prompt_tokens']}, "
                f"Completion tokens: {usage_totals['completion_tokens']}, "
                f"Total tokens: {usage_totals['total_tokens']}"
            )
            if usage_totals["prompt_cache_read_tokens"] or usage_totals[
                "prompt_cache_write_tokens"
            ]:
                print(
                    "Prompt cache tokens: "
                    f"reads={usage_totals['prompt_cache_read_tokens']}, "
                    f"writes={usage_totals['prompt_cache_write_tokens']}"
                )
            cds = usage_totals["cache_discounts"]
            if cds:
                avg_cd = sum(cds) / len(cds)
                print(f"Average cache_discount: {avg_cd:.3f}")
        else:
            print("\nNo story was created.")

    except KeyboardInterrupt:
        print("\n\nInterrupted. Goodbye.")
        if story:
            _save_story(story, model, model_source or "unknown", turn_logs)
            # Even on interrupt, print whatever usage we have so far.
            print("\n=== Session usage summary (partial) ===")
            print(f"Requests: {usage_totals['requests']}")
            print(
                f"Prompt tokens: {usage_totals['prompt_tokens']}, "
                f"Completion tokens: {usage_totals['completion_tokens']}, "
                f"Total tokens: {usage_totals['total_tokens']}"
            )


if __name__ == "__main__":
    main()


