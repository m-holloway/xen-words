"""
Mad Libs story blueprint generator (Stage 1 of DG library-building).

This script asks a strong, taste-focused model (e.g. google/gemini-3-pro-preview)
to propose multiple high-level story blueprints in one call. Each blueprint
captures a reusable narrative pattern (premise, setting, emotional arc, and
must-have moments) that can later be instantiated into concrete Mad Libs
templates by a faster generator model.

Blueprints are intentionally abstract enough to support many variants, but
grounded in proven children's story patterns (quest, problem–solution, buddy
story, mystery, etc.), and tuned for Level 3 (approx. Grades 1–2).
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


def _blueprint_system_prompt() -> str:
    return (
        "You are an award-winning children's author and story developer.\n"
        "We are building a library of high-quality story blueprints for Level 3\n"
        "readers (approx. ages 6–8, Grades 1–2). These blueprints will later be\n"
        "used to generate many concrete Mad Libs–style story templates.\n\n"
        "Your task is to propose several DISTINCT story blueprints. Each blueprint\n"
        "is a reusable narrative pattern, not a full story. We want patterns that:\n"
        "- Are grounded in real-world successful picture-book / early-reader arcs.\n"
        "- Leave plenty of room for creative variation (different characters,\n"
        "  settings, and specific events), while still giving a clear, proven shape.\n"
        "- Are cozy, hopeful, and appropriate for ages 6–8 (no real-world trauma,\n"
        "  no death, no cruelty; small problems, big feelings, gentle resolutions).\n\n"
        "Think in terms of patterns like:\n"
        "- Curiosity quest: a child notices something odd and goes on a gentle\n"
        "  adventure to understand it.\n"
        "- Buddy story: an unlikely friendship forms between the child and a\n"
        "  creature/object/neighbor, with a moment of conflict and repair.\n"
        "- Problem–solution story: a small but real problem (lost item, minor fear,\n"
        "  sibling conflict, classroom hiccup) is worked through in 2–3 steps.\n"
        "- Everyday magic: something ordinary (a bus ride, bedtime, grocery trip)\n"
        "  reveals a hidden magical twist, which changes how the child sees the\n"
        "  world or themselves.\n"
        "- Growth moment: the child has to choose between two impulses (e.g., keep\n"
        "  vs share, hide vs tell the truth, give up vs try again) and grows a\n"
        "  little when they choose the kinder or braver path.\n\n"
        "We are especially interested in patterns that:\n"
        "- Invite a vivid, specific centerpiece image or scene that a child might\n"
        "  describe later (\"the robot that shelved books by itself\", \"the snail\n"
        "  with a map on its shell\", etc.).\n"
        "- Can be retold in 2–3 simple sentences by a 6–8 year old.\n"
        "- Are NOT just variations on the same 'lost balloon/kite/toy in a park'\n"
        "  pattern. Avoid reusing that exact motif.\n"
        "- Can be adapted to many settings (home, school, playground, library,\n"
        "  beach, bus ride, sleepover, etc.).\n\n"
        "You will receive a JSON user message with fields like `count` and\n"
        "`exploration_ratio`.\n"
        "- Generate exactly `count` blueprints.\n"
        "- Aim for roughly `(1 - exploration_ratio)` of them to feel like strong,\n"
        "  cozy, on-pattern picture-book blueprints that could sit beside the best\n"
        "  books in a school library.\n"
        "- Aim for roughly `exploration_ratio` of them to *deliberately push the\n"
        "  frame* while still being age-appropriate and coherent. These \"frame\n"
        "  breakers\" might use less typical settings (laundromat at night,\n"
        "  rooftop garden, city bus depot), unusual story devices (a story told\n"
        "  through notes or drawings), or surprising emotional angles (quiet envy\n"
        "  that turns into mentoring), but must stay gentle and hopeful.\n\n"
        "For each blueprint, you will provide:\n"
        "- `id`: a short identifier like \"bp_library_robot\".\n"
        "- `pattern_name`: a short, human-readable label for the pattern\n"
        "  (e.g., \"Curious Machine Mystery\").\n"
        "- `logline`: 1–2 sentences describing the core idea.\n"
        "- `setting`: a typical setting or category of settings that fit this\n"
        "  pattern (e.g., \"school library\", \"grandparent's house\", \"bus ride\").\n"
        "- `emotional_theme`: e.g. curiosity, courage, sharing, empathy, patience.\n"
        "- `age_range`: a short string like \"6–8\".\n"
        "- `beats`: 4–6 high-level beats (beginning, build, turn, resolution),\n"
        "  each with an `id`, a `role` (e.g., \"hook\", \"escalation\", \"twist\",\n"
        "  \"resolution\"), and a 1–2 sentence `description` of what happens.\n"
        "- `centerpiece_moment`: a single vivid scene or image that should appear\n"
        "  in every story using this blueprint.\n"
        "- `slot_ideas`: 4–7 suggested Mad Libs slots as objects with:\n"
        "  * `id`: e.g. \"slot_child\", \"slot_sidekick\", \"slot_special_object\".\n"
        "  * `type`: a short type label (\"child_name\", \"animal_pet\",\n"
        "     \"favorite_activity\", \"place_name\", \"snack_food\", etc.).\n"
        "  * `role`: how this slot functions in the story (e.g., \"main character\",\n"
        "     \"helpful sidekick\", \"thing that goes missing\", \"place of surprise\").\n"
        "  * `examples`: 3–5 example fills appropriate for Level 3.\n\n"
        "Output STRICT JSON only, no commentary. Use this schema:\n"
        "{\n"
        "  \"blueprints\": [\n"
        "    {\n"
        "      \"id\": \"bp_example\",\n"
        "      \"pattern_name\": \"Curious Attic Mystery\",\n"
        "      \"logline\": \"A curious child discovers a strange object in the attic and\n"
        "                   follows clues to learn its story.\",\n"
        "      \"setting\": \"attic in a family home\",\n"
        "      \"emotional_theme\": \"curiosity and courage\",\n"
        "      \"age_range\": \"6–8\",\n"
        "      \"beats\": [\n"
        "        {\"id\": \"beginning\", \"role\": \"hook\", \"description\": \"The child\n"
        "          notices something unusual in a familiar place and decides to\n"
        "          investigate.\"},\n"
        "        {\"id\": \"middle1\", \"role\": \"exploration\", \"description\": \"The\n"
        "          child tries one simple idea to understand the object, but it\n"
        "          doesn't fully work.\"},\n"
        "        {\"id\": \"middle2\", \"role\": \"twist\", \"description\": \"A small\n"
        "          surprise reveals that the object is connected to someone else in\n"
        "          the child's life.\"},\n"
        "        {\"id\": \"resolution\", \"role\": \"sharing\", \"description\": \"The\n"
        "          child chooses a kind or brave action that brings the object to\n"
        "          its right place and leaves everyone feeling warm and satisfied.\"}\n"
        "      ],\n"
        "      \"centerpiece_moment\": \"The child opens an old box and a faint glow\n"
        "         spills out, revealing a tiny music box that plays a tune from long\n"
        "         ago.\",\n"
        "      \"slot_ideas\": [\n"
        "        {\"id\": \"slot_child\", \"type\": \"child_name\", \"role\": \"protagonist\",\n"
        "         \"examples\": [\"Mia\", \"Jamal\", \"Sofia\"]},\n"
        "        {\"id\": \"slot_caregiver\", \"type\": \"family_member\", \"role\": \"adult\n"
        "         who knows the secret\", \"examples\": [\"Grandma\", \"Uncle\", \"Dad\"]},\n"
        "        {\"id\": \"slot_object\", \"type\": \"special_object\", \"role\": \"mysterious\n"
        "         thing in the attic\", \"examples\": [\"music box\", \"old camera\",\n"
        "         \"glowing rock\"]},\n"
        "        {\"id\": \"slot_place\", \"type\": \"place_name\", \"role\": \"where the\n"
        "         object truly belongs\", \"examples\": [\"park\", \"museum\",\n"
        "         \"grandma's room\"]}\n"
        "      ]\n"
        "    }\n"
        "  ]\n"
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
        "X-Title": "Xen Words - Mad Libs Blueprint Generator",
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
        "temperature": 0.9,
        "max_output_tokens": 2048,
        "usage": {"include": True},
        "user": "madlibs_blueprint_generator",
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
    Extract the first balanced JSON object from a text that may contain
    extra commentary or whitespace around it.
    """
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


def _parse_blueprints(content: str) -> List[MadLibsBlueprint]:
    extracted = _extract_first_json_object(content)
    data = json.loads(extracted)
    raw_list = data.get("blueprints", [])
    result: List[MadLibsBlueprint] = []
    for obj in raw_list:
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
        result.append(bp)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate high-level Mad Libs story blueprints using a strong model."
    )
    parser.add_argument(
        "--count",
        type=int,
        default=6,
        help="Number of blueprints to request in one batch (default: 6).",
    )
    parser.add_argument(
        "--exploration-ratio",
        type=float,
        default=0.3,
        help=(
            "Target fraction of blueprints that should be deliberate frame-"
            "breakers (default: 0.3)."
        ),
    )
    parser.add_argument(
        "--model",
        type=str,
        default="google/gemini-3-pro-preview",
        help="OpenRouter model id to use for blueprint generation.",
    )
    args = parser.parse_args()

    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")

    system = _blueprint_system_prompt()
    user_payload = {
        "level": 3,
        "count": args.count,
        "exploration_ratio": args.exploration_ratio,
    }

    print(
        f"Requesting {args.count} blueprints from model={args.model} for Level 3 readers..."
    )
    try:
        data = _call_openrouter(
            api_key=api_key,
            model=args.model,
            system=system,
            user_payload=user_payload,
        )
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenRouter HTTPError {e.code}: {body[:400]}") from e
    except Exception as e:
        raise SystemExit(f"OpenRouter request failed: {e}") from e

    usage = data.get("usage")
    if isinstance(usage, dict):
        print(f"Blueprint generation usage: {usage}")

    # OpenRouter returns the assistant message as either plain text or a list
    # of segments; we handle the plain-text case which is what we expect from
    # JSON-oriented models.
    content = data["choices"][0]["message"]["content"]
    text = _strip_markdown_fences(str(content or ""))
    blueprints = _parse_blueprints(text)

    out_dir = Path(__file__).parent / "generated_madlibs_stories"
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = out_dir / f"blueprints_level3_{ts}.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "config": {
                    "model": args.model,
                    "count": args.count,
                },
                "blueprints": [asdict(b) for b in blueprints],
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
    print(f"Saved {len(blueprints)} blueprints to: {json_path}")

    # Print a brief summary for quick human inspection.
    print("\n=== Blueprint summaries ===")
    for bp in blueprints:
        print(f"- {bp.id or '[no-id]'} :: {bp.pattern_name} — {bp.logline}")


if __name__ == "__main__":
    main()


