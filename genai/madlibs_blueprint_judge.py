"""
Judge and rank Mad Libs story blueprints, DG-style.

This script:
- Loads all blueprint JSON files in `generated_madlibs_stories/` whose
  filenames start with `blueprints_level3_`.
- Calls a judge model (default: google/gemini-3-pro-preview) via OpenRouter
  to score each blueprint on qualitative axes (arc potential, warmth, novelty,
  variety potential, kid-retellability, etc.).
- Writes a judged catalog JSON with scores and prints a small "hall of fame"
  list sorted by overall score.

This is a DG-style step over the *blueprints themselves* so that later
generation can sample from the best 50–100 patterns instead of the full
unfiltered set.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

import urllib.error
import urllib.request

from madlibs_story_generator import load_env


@dataclass
class BlueprintBeat:
    id: str
    role: str
    description: str


@dataclass
class BlueprintSlotIdea:
    id: str
    type: str
    role: str
    examples: List[str]


@dataclass
class MadLibsBlueprint:
    id: str
    pattern_name: str
    logline: str
    setting: str
    emotional_theme: str
    age_range: str
    beats: List[BlueprintBeat]
    centerpiece_moment: str
    slot_ideas: List[BlueprintSlotIdea]


@dataclass
class BlueprintWithMeta:
    source_file: str
    index_in_file: int
    blueprint: MadLibsBlueprint


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
    stripped = _strip_markdown_fences(text)
    start = -1
    depth = 0
    for i, ch in enumerate(stripped):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            if depth > 0:
                depth -= 1
                if depth == 0 and start != -1:
                    end = i
                    return stripped[start : end + 1]
    raise json.JSONDecodeError("No balanced JSON object found", stripped, 0)


def _blueprint_judge_system_prompt() -> str:
    return (
        "You are a very thoughtful children's-story development editor.\n"
        "You are judging *story blueprints* for Level 3 readers (approx. ages 6–8).\n"
        "Each blueprint is a reusable pattern, not a full manuscript. We want\n"
        "blueprints that could lead to many distinct, cozy, high-quality stories.\n\n"
        "You will be given one blueprint at a time as JSON with fields like\n"
        "`pattern_name`, `logline`, `setting`, `emotional_theme`, `beats`,\n"
        "`centerpiece_moment`, and `slot_ideas`.\n\n"
        "Please score the blueprint on these axes (0.0–1.0 floats):\n"
        "- overall: Your holistic sense of how strong this blueprint is as a\n"
        "  seed for many great Level 3 stories. Calibrate:\n"
        "  * 0.9–1.0: Exceptional; feels like it could anchor a beloved mini-series\n"
        "    of picture books; strong arc, emotion, and kid appeal.\n"
        "  * 0.7–0.85: Strong; clearly above average, would happily keep in a\n"
        "    curated library.\n"
        "  * 0.4–0.65: Generic-but-okay; fine, but not special.\n"
        "  * < 0.4: Weak; confusing, thin, or too derivative.\n"
        "- story_arc_potential: How clearly the beats support a satisfying\n"
        "  beginning–middle–turn–resolution for small problems and big feelings.\n"
        "- emotional_warmth: How cozy, kind, and emotionally resonant the pattern\n"
        "  can be when instantiated.\n"
        "- novelty: How fresh this blueprint feels compared to very common\n"
        "  early-reader tropes (lost generic toy in park, plain bedtime, plain\n"
        "  \"share your snack\" with no twist). Reward unusual but kid-friendly\n"
        "  settings, devices, or centerpiece moments.\n"
        "- variety_potential: How many *different* concrete stories you could\n"
        "  imagine building from this one blueprint by swapping characters,\n"
        "  details, and settings while keeping the pattern.\n"
        "- kid_retellability: How easy it would be for a 6–8 year old to retell\n"
        "  the core story in 2–3 simple sentences after hearing it.\n"
        "- blueprint_clarity: How clearly the beats and slot ideas communicate\n"
        "  what should happen, without being muddled or over-complex.\n\n"
        "Also include a short free-text `one_line_feedback` giving a sharp,\n"
        "editorial reaction (e.g., \"Lovely emotional turn but pattern feels very\n"
        "close to standard stage-fright stories\" or \"Setting/device feel fresh and\n"
        "kid-memorable; easy to vary.\").\n\n"
        "Return STRICT JSON with this shape:\n"
        "{\n"
        "  \"overall\": 0.0,\n"
        "  \"story_arc_potential\": 0.0,\n"
        "  \"emotional_warmth\": 0.0,\n"
        "  \"novelty\": 0.0,\n"
        "  \"variety_potential\": 0.0,\n"
        "  \"kid_retellability\": 0.0,\n"
        "  \"blueprint_clarity\": 0.0,\n"
        "  \"one_line_feedback\": \"...\"\n"
        "}\n"
    )


def _call_openrouter(
    *,
    api_key: str,
    model: str,
    system: str,
    user_payload: Dict[str, Any],
) -> Dict[str, Any]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Mad Libs Blueprint Judge",
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
                "content": json.dumps(user_payload, ensure_ascii=False),
                "cache_control": {"type": "ephemeral"},
            },
        ],
        "temperature": 0.1,
        "max_output_tokens": 512,
        "usage": {"include": True},
        "user": "madlibs_blueprint_judge",
    }
    data_bytes = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", method="POST"
    )
    for k, v in headers.items():
        req.add_header(k, v)
    req.data = data_bytes

    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)


def _load_all_blueprints(root: Path) -> List[BlueprintWithMeta]:
    out: List[BlueprintWithMeta] = []
    for path in sorted(root.glob("blueprints_level3_*.json")):
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        for idx, obj in enumerate(data.get("blueprints", [])):
            beats = [
                BlueprintBeat(
                    id=b.get("id", ""),
                    role=b.get("role", ""),
                    description=b.get("description", ""),
                )
                for b in (obj.get("beats") or [])
            ]
            slots = [
                BlueprintSlotIdea(
                    id=s.get("id", ""),
                    type=s.get("type", ""),
                    role=s.get("role", ""),
                    examples=[str(e) for e in (s.get("examples") or [])],
                )
                for s in (obj.get("slot_ideas") or [])
            ]
            bp = MadLibsBlueprint(
                id=obj.get("id", ""),
                pattern_name=obj.get("pattern_name", ""),
                logline=obj.get("logline", ""),
                setting=obj.get("setting", ""),
                emotional_theme=obj.get("emotional_theme", ""),
                age_range=obj.get("age_range", ""),
                beats=beats,
                centerpiece_moment=obj.get("centerpiece_moment", ""),
                slot_ideas=slots,
            )
            out.append(
                BlueprintWithMeta(
                    source_file=str(path.name), index_in_file=idx, blueprint=bp
                )
            )
    return out


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Judge and rank all Level 3 Mad Libs blueprints using an LLM judge."
        )
    )
    parser.add_argument(
        "--judge-model",
        type=str,
        default="google/gemini-3-pro-preview",
        help="OpenRouter model id to use as the blueprint judge.",
    )
    args = parser.parse_args()

    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")

    root = Path(__file__).parent / "generated_madlibs_stories"
    blueprints = _load_all_blueprints(root)
    if not blueprints:
        raise SystemExit("No blueprints_level3_*.json files found to judge.")

    print(f"Loaded {len(blueprints)} blueprints from {root}")

    system = _blueprint_judge_system_prompt()
    judged_entries: List[Dict[str, Any]] = []

    for i, wrapped in enumerate(blueprints, start=1):
        bp = wrapped.blueprint
        print(f"Judging {i}/{len(blueprints)}: {bp.id or '[no-id]'} :: {bp.pattern_name}")
        user_payload = {
            "blueprint": {
                "id": bp.id,
                "pattern_name": bp.pattern_name,
                "logline": bp.logline,
                "setting": bp.setting,
                "emotional_theme": bp.emotional_theme,
                "age_range": bp.age_range,
                "beats": [asdict(b) for b in bp.beats],
                "centerpiece_moment": bp.centerpiece_moment,
                "slot_ideas": [asdict(s) for s in bp.slot_ideas],
            }
        }
        try:
            data = _call_openrouter(
                api_key=api_key,
                model=args.judge_model,
                system=system,
                user_payload=user_payload,
            )
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            print(f"HTTPError judging blueprint {bp.id}: {e.code} {body[:200]}")
            continue
        except Exception as e:
            print(f"Error judging blueprint {bp.id}: {e}")
            continue

        usage = data.get("usage")
        if isinstance(usage, dict):
            print(
                f"  usage: prompt={usage.get('prompt_tokens')} "
                f"completion={usage.get('completion_tokens')} "
                f"cost={usage.get('cost')}"
            )

        content = data["choices"][0]["message"]["content"]
        text = _strip_markdown_fences(str(content or ""))
        try:
            obj = json.loads(_extract_first_json_object(text))
        except json.JSONDecodeError as e:
            print(f"  Failed to parse judge JSON for {bp.id}: {e}")
            continue

        judged_entries.append(
            {
                "source_file": wrapped.source_file,
                "index_in_file": wrapped.index_in_file,
                "blueprint": asdict(bp),
                "judge_model": args.judge_model,
                "scores": obj,
            }
        )

    if not judged_entries:
        raise SystemExit("No judged entries produced; aborting.")

    # Sort by overall, then novelty as tiebreaker.
    judged_entries.sort(
        key=lambda e: (
            float(e["scores"].get("overall", 0.0)),
            float(e["scores"].get("novelty", 0.0)),
        ),
        reverse=True,
    )

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path = root / f"blueprints_level3_judged_{ts}.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "meta": {
                    "judge_model": args.judge_model,
                    "timestamp": ts,
                    "total_blueprints": len(blueprints),
                    "judged_count": len(judged_entries),
                },
                "entries": judged_entries,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
    print(f"\nSaved judged blueprints catalog to: {out_path}")

    # Print a small hall-of-fame preview.
    print("\n=== Hall of fame preview (top 12 by overall) ===")
    for entry in judged_entries[:12]:
        bp = entry["blueprint"]
        scores = entry["scores"]
        print(
            f"- {bp.get('id') or '[no-id]'} :: {bp.get('pattern_name')} "
            f"(overall={scores.get('overall'):.3f}, "
            f"novelty={scores.get('novelty'):.3f})"
        )


if __name__ == "__main__":
    main()


