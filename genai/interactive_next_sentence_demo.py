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
        "  * Build directly on the child's idea and the current story context.\n"
        "  * Match the current beat goal and target tension.\n"
        "  * Align with the family's values and content boundaries.\n"
        "  * Fit the reading level while keeping language vivid and joyful.\n"
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
) -> Dict[str, Any]:
    """
    Build the JSON payload for the next-sentence request.

    - `story_so_far` is the list of sentences already chosen.
    - `child_line` is the most recent line the user added (seed for this turn).
    """
    values = ValuesGoals(
        core_values=["kindness", "courage", "curiosity"],
        skill_focus=["trying_new_things", "asking_for_help"],
        tone_preferences={"humor": "gentle", "tension": "low", "pace": "cozy"},
        content_boundaries={
            "avoid": ["bullying", "realistic injury", "death of family members"],
            "soften": ["monsters", "storms"],
        },
        family_context_notes="Child sometimes worries about new situations; keep things cozy and safe.",
    )

    # Build a lightweight textual context from the running story.
    if story_so_far:
        narrator_text = "\n".join(story_so_far)
    else:
        narrator_text = "It was a soft, cloudy evening by the pond."

    effective_child_line = child_line or "The turtle finds a glowing rock."

    return {
        "context": {
            "story_id": "demo_story",
            "plan_id": "plan_1",
            "profile_id": "child_1",
            "reading_level": 2,
            "reading_band": {"grade_band": "K-1"},
            "parent_prompt": "A cozy adventure with a shy turtle who learns to be brave.",
            "child_context": "Loves turtles and space; sometimes worried about new things.",
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
        # Use the same Gemini 2.5 Flash ID you have configured in ModelConfig.
        model = "google/gemini-2.5-flash-preview-09-2025"
        model_source = "hardcoded fallback (gemini-2.5-flash-preview-09-2025)"

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

    print("\n=== Interactive Story Builder (one sentence at a time) ===")

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

            start_choice = input("Choose A/B, C to write your own, or D to reshuffle: ").strip().upper()
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

        # If the fragment contains a blank, let the user fill it.
        if "____" in base_opening:
            fill = input(
                "Fill in the blank (e.g., 'curious turtle', 'kind robot'), "
                "or press Enter to keep it as-is: "
            ).strip()
            if fill:
                base_opening = base_opening.replace("_____", fill).replace("____", fill)
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
            )
            payload["tuning_tokens"] = tuning_tokens

            body = {
                "model": model,
                "messages": [
                    {"role": "system", "content": _system_prompt()},
                    {
                        "role": "user",
                        "content": json.dumps(payload, ensure_ascii=False),
                    },
                ],
                "temperature": 0.85,
                "max_output_tokens": 512,
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
        else:
            print("\nNo story was created.")

    except KeyboardInterrupt:
        print("\n\nInterrupted. Goodbye.")
        if story:
            _save_story(story, model, model_source or "unknown", turn_logs)


if __name__ == "__main__":
    main()


