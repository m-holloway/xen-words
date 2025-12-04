"""
Instantiate Mad Libs story templates from high-level blueprints.

This script takes a single blueprint (from the judged blueprint catalog)
and asks a fast generator model (e.g. inception/mercury) to turn that
pattern into a concrete Mad Libs–style story template.

Goal: validate whether the blueprint concept actually leads to better,
more varied templates before we scale out a huge blueprint catalog.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

import urllib.error

from madlibs_story_generator import (
    MadLibStoryTemplate,
    _call_openrouter,
    _extract_first_json_object,
    _parse_template,
    _save_template,
    _strip_markdown_fences,
    load_env,
    load_sampling_config,
)


def _instantiation_system_prompt() -> str:
    """
    System prompt for turning a blueprint into a concrete Mad Libs template.
    """
    return (
        "You are an expert children's-story author and game designer.\n"
        "You will receive:\n"
        "- A target reading level (around Level 3, ages 6–8).\n"
        "- A high-level STORY BLUEPRINT describing a reusable pattern:\n"
        "  pattern_name, logline, setting, emotional_theme, beats, a\n"
        "  centerpiece_moment, and slot_ideas.\n\n"
        "Your job is to turn this blueprint into ONE specific Mad Libs–style\n"
        "story template that could go in a Level 3 reading app.\n\n"
        "Follow these rules:\n"
        "- Honor the blueprint's core arc:\n"
        "  * The beats should map onto the story's beginning, middle, small twist,\n"
        "    and resolution.\n"
        "  * The centerpiece_moment should appear as a vivid image or short scene\n"
        "    in the story text.\n"
        "- Keep the emotional_theme clear but shown through actions, not blunt\n"
        "  morals. Avoid sentences like \"They learned that sharing is good.\"\n"
        "- Use a warm, hopeful tone with small but real feelings.\n\n"
        "Reading level / language:\n"
        "- Aim for Level 3 (roughly Grades 1–2): short-to-medium sentences,\n"
        "  mostly high-frequency words plus a few richer ones.\n"
        "- No dark or frightening content; problems are small and solvable.\n\n"
        "Mad Libs constraints:\n"
        "- Represent blanks with double square brackets, e.g. [[slot_pet]].\n"
        "- Use the blueprint's slot_ideas as a starting point for slots, but you\n"
        "  may rename ids slightly if needed for clarity (keep them stable).\n"
        "- For each slot, you MUST provide:\n"
        "  * id\n"
        "  * type (specific, low-level, like child_name, animal_pet,\n"
        "    favorite_activity, snack_food, place_name, magical_entity)\n"
        "  * author_description (what goes here)\n"
        "  * child_prompt (spoken prompt to ask the kid for a word)\n"
        "  * 3–5 example fills.\n"
        "- Keep sentences natural even with blanks; when filled, the story should\n"
        "  read smoothly out loud.\n"
        "- IMPORTANT: Do NOT put the core story problem, turning decision, or\n"
        "  resolution into blanks. Those must be fully specified in the text.\n"
        "  Blanks are ONLY for concrete, easily swappable details.\n\n"
        "Story structure:\n"
        "- Aim for 8–14 sentences total.\n"
        "- Early sentences should establish the setting, main character, and\n"
        "  small problem or question.\n"
        "- Middle sentences should explore or escalate in gentle ways, roughly\n"
        "  following the blueprint beats.\n"
        "- The last 2–3 sentences should clearly resolve the small problem and\n"
        "  leave a warm after-feeling.\n\n"
        "Output STRICT JSON only, no markdown or commentary. Use this schema:\n"
        "{\n"
        '  \"title\": \"...\",\n'
        '  \"reading_level\": 3,\n'
        '  \"reading_band\": \"Grades 1–2\",\n'
        '  \"target_minutes\": 5,\n'
        '  \"summary\": \"One-sentence parent-facing summary.\",\n'
        '  \"slots\": [\n'
        "    {\n"
        '      \"id\": \"slot_child\",\n'
        '      \"type\": \"child_name\",\n'
        '      \"author_description\": \"Name of the child main character.\",\n'
        '      \"child_prompt\": \"What is a name you like for the kid in this story?\",\n'
        '      \"examples\": [\"Mia\", \"Jamal\", \"Sofia\"]\n'
        "    }\n"
        "  ],\n"
        '  \"sentences\": [\n'
        "    {\n"
        '      \"id\": \"s1\",\n'
        '      \"text_with_blanks\": \"[[slot_child]] stared out the window of the [[slot_vehicle]].\",\n'
        '      \"slot_ids\": [\"slot_child\", \"slot_vehicle\"]\n'
        "    }\n"
        "  ]\n"
        "}\n"
    )


def _load_latest_judged_catalog(root: Path) -> Path:
    candidates = sorted(root.glob("blueprints_level3_judged_*.json"))
    if not candidates:
        raise SystemExit("No blueprints_level3_judged_*.json catalog found.")
    return candidates[-1]


def _load_blueprint_from_catalog(catalog_path: Path, blueprint_id: str) -> Dict[str, Any]:
    with catalog_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    for entry in data.get("entries", []):
        bp = entry.get("blueprint") or {}
        if bp.get("id") == blueprint_id:
            return bp
    raise SystemExit(f"Blueprint id '{blueprint_id}' not found in {catalog_path}")


def instantiate_from_blueprint(
    *,
    blueprint: Dict[str, Any],
    level: int,
    model: str,
    temperature: float,
) -> MadLibStoryTemplate:
    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")

    system = _instantiation_system_prompt()
    # Keep constraints similar to the plain generator but include the blueprint.
    if level <= 2:
        band = "K–1"
        target_minutes = 3
    elif level == 3:
        band = "Grades 1–2"
        target_minutes = 5
    else:
        band = "Grades 2–3"
        target_minutes = 6

    user_payload: Dict[str, Any] = {
        "reading_level": level,
        "reading_band": band,
        "target_minutes": target_minutes,
        "blueprint": blueprint,
        "constraints": {
            "max_sentences": 14,
            "min_sentences": 8,
            "max_slots": 8,
            "tone": "warm, curious, gently playful",
            "avoid": ["bullying", "realistic injury", "death"],
        },
    }

    print(
        f"Calling {model} to instantiate blueprint "
        f"{blueprint.get('id')} ({blueprint.get('pattern_name')})..."
    )
    try:
        data = _call_openrouter(
            api_key=api_key,
            model=model,
            system=system,
            user_payload=user_payload,
            temperature=temperature,
        )
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenRouter HTTPError {e.code}: {body[:400]}") from e
    except Exception as e:
        raise SystemExit(f"OpenRouter request failed: {e}") from e

    usage = data.get("usage")
    if usage:
        print(f"Usage: {usage}")

    content = data["choices"][0]["message"]["content"]
    text = _strip_markdown_fences(str(content or ""))
    # We expect a single template object.
    json_str = _extract_first_json_object(text)
    template = _parse_template(json_str)
    return template


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Instantiate a Mad Libs story template from a judged blueprint "
            "to validate blueprint usefulness."
        )
    )
    parser.add_argument(
        "--blueprint-id",
        type=str,
        required=True,
        help="ID of the blueprint to instantiate (e.g. bp_magic_transit).",
    )
    parser.add_argument(
        "--judged-file",
        type=str,
        default=None,
        help=(
            "Path to a blueprints_level3_judged_*.json catalog. "
            "If omitted, uses the latest one."
        ),
    )
    parser.add_argument(
        "--level",
        type=int,
        default=3,
        help="Target reading level (default: 3).",
    )
    parser.add_argument(
        "--model",
        type=str,
        default="inception/mercury",
        help="Generator model to use (default: inception/mercury).",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=None,
        help=(
            "Sampling temperature. If omitted, uses generator_temperature "
            "from madlibs_dg_config.json."
        ),
    )
    args = parser.parse_args()

    sampling_cfg = load_sampling_config()
    temperature = args.temperature
    if temperature is None:
        temperature = float(sampling_cfg.get("generator_temperature", 0.9))

    root = Path(__file__).parent / "generated_madlibs_stories"
    if args.judged_file:
        catalog_path = Path(args.judged_file)
    else:
        catalog_path = _load_latest_judged_catalog(root)

    print(f"Using judged catalog: {catalog_path}")
    blueprint = _load_blueprint_from_catalog(catalog_path, args.blueprint_id)

    template = instantiate_from_blueprint(
        blueprint=blueprint,
        level=args.level,
        model=args.model,
        temperature=temperature,
    )
    meta = {
        "generator_model": args.model,
        "generator_temperature": temperature,
        "blueprint_id": blueprint.get("id"),
        "blueprint_pattern_name": blueprint.get("pattern_name"),
        "blueprint_logline": blueprint.get("logline"),
        "blueprint_instantiated_at": datetime.now().isoformat(timespec="seconds"),
    }
    _save_template(template, meta=meta)


if __name__ == "__main__":
    main()


