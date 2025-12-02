"""
Mad Libs–style story template generator for the Xen Words app.

Goal for this first step:
- Use an LLM (e.g. inception/mercury on OpenRouter) to generate a single,
  high-quality, level-tagged Mad Libs story template with:
  - A short, coherent story arc (ideally Level 2–3).
  - Sentences that include typed blanks.
  - Per-blank metadata:
    - description for the author,
    - kid-facing spoken prompt ("Can you name a toy you like to play with?").
- Save results to JSON so we can build a reusable library for the app.

Usage (from repo root):
    cd genai
    python madlibs_story_generator.py --level 3 --model inception/mercury

Notes:
- This is an offline / library-building tool, not part of the live interactive loop.
- We keep the code simple and dependency-light (urllib + json).
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
import time

import urllib.error
import urllib.request


# --- Config / helpers -------------------------------------------------------


def load_env() -> Dict[str, str]:
    """
    Minimal .env loader for the `genai` directory.
    Mirrors the pattern used in other genai Python scripts.
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
                value = value.split("#", 1)[0].strip()
                if key:
                    env_vars[key] = value
    # Overlay process env (gives you a way to override quickly).
    env_vars.update({k: v for k, v in os.environ.items() if k not in env_vars})
    return env_vars


def load_sampling_config() -> Dict[str, Any]:
    """
    Load sampling / temperature configuration for Mad Libs DG experiments.
    Falls back to sensible defaults if the config file is missing or invalid.
    """
    config_path = Path(__file__).parent / "madlibs_dg_config.json"
    default_cfg: Dict[str, Any] = {
        "generator_temperature": 0.9,
        "evolver_generator_temperature": 0.9,
        "refiner_temperature": 0.4,
        "judge_temperature": 0.1,
    }
    if not config_path.exists():
        return default_cfg
    try:
        with config_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return default_cfg
        # Overlay file contents onto defaults so missing keys still get defaults.
        merged = {**default_cfg, **data}
        return merged
    except Exception:
        # On any parse error, just use defaults so scripts don't break.
        return default_cfg


@dataclass
class MadLibSlot:
    id: str
    type: str
    author_description: str
    child_prompt: str
    examples: List[str]


@dataclass
class MadLibSentence:
    id: str
    text_with_blanks: str  # e.g., "The [[slot_pet]] liked to jump."
    slot_ids: List[str]


@dataclass
class MadLibStoryTemplate:
    title: str
    reading_level: int
    reading_band: str
    target_minutes: int
    summary: str
    sentences: List[MadLibSentence]
    slots: List[MadLibSlot]


GENERATOR_PROMPT_VERSION = "G3_patterns_menu_innerChoice_showDontTell"


def _system_prompt() -> str:
    return (
        "You are designing a short children's story as a Mad Libs–style template.\n"
        "The audience is an early reader around reading level 2–3 (Grades 1–2).\n\n"
        "Your goals:\n"
        "- Create a warm, coherent story arc that a child can enjoy in about 5 minutes.\n"
        "- The story should have:\n"
        "  * A clear main character.\n"
        "  * A small, gentle problem or question.\n"
        "  * A soft, satisfying resolution.\n"
        "- Language should roughly match reading level 3:\n"
        "  * Sentences are short-to-medium length.\n"
        "  * Mostly high-frequency words, with a few richer words.\n"
        "  * No dark or frightening content.\n\n"
        "Story qualities beyond mechanics (aims, not rigid rules):\n"
        "- Aim to include at least ONE slightly surprising or vivid image that a child might remember\n"
        "  later (e.g., a funny action, an unusual but cozy comparison).\n"
        "- Aim to include at least ONE brief inner decision moment for the child character:\n"
        "  they almost do one thing, but then choose a kinder or braver option instead.\n"
        "- Prefer to show lessons through actions and images instead of stating them directly.\n"
        "  Avoid on-the-nose moral sentences like \"They learned that sharing is good\"; let the\n"
        "  scenes make that clear.\n\n"
        "Story pattern guidance (to avoid feeling too generic):\n"
        "- Try not to rely only on very common patterns such as:\n"
        "  * a plain lost balloon or kite in a park that is simply found and then they share a snack,\n"
        "  * a generic \"lost toy at the park\" that is found immediately with no interesting twist.\n"
        "- If you do use these familiar patterns, consider adding a fresh, cozy element so the story\n"
        "  feels like its own thing (for example, a toy that hums when it is happy, or a kite that\n"
        "  responds to kindness).\n"
        "- You may choose from many effective child-friendly story shapes. For example (choose or\n"
        "  blend ideas; you do NOT need to follow these mechanically):\n"
        "  * Curiosity pattern: the child wonders about something small, explores carefully, and\n"
        "    discovers a gentle surprise.\n"
        "  * Helping pattern: the child notices someone or something having a small problem and\n"
        "    chooses to help in more than one small way.\n"
        "  * Try–try–succeed pattern: the child tries one simple idea, then a second, and finally\n"
        "    finds a kind or clever approach that works.\n"
        "  * Sharing pattern: the child almost keeps something just for themselves, then decides to\n"
        "    share it, which makes the moment more special.\n"
        "- Treat these as a menu of good options, not strict templates. You can invent your own\n"
        "  pattern as long as it stays gentle, clear, and appropriate for a Level 3 reader.\n"
        "- You may place the story in a wide range of everyday, appealing settings for a child this\n"
        "  age (home, school, park, garden, backyard, bus ride, classroom, etc.). Avoid scary or\n"
        "  heavy locations, but feel free to be playful and varied.\n\n"
        "Mad Libs constraints:\n"
        "- Represent blanks with double square brackets, e.g. [[slot_pet]].\n"
        "- Each blank must have:\n"
        "  * a stable slot id,\n"
        "  * a short author-facing description (what kind of word/phrase goes here),\n"
        "  * a kid-facing spoken prompt (how we ask the child for a word),\n"
        "  * a few example fills.\n"
        "- Keep sentences natural even with blanks; when a real word is inserted,\n"
        "  the sentence should read smoothly out loud.\n"
        "- IMPORTANT: Do NOT put the core story problem, goal, or resolution into a\n"
        "  blank. Those must be fully specified in the text. Blanks are ONLY for\n"
        "  concrete, easily substitutable details: toys, animals, favorite foods,\n"
        "  colors, simple activities, place names, etc.\n"
        "- Avoid broad or abstract slot types like `slot_problem`, `slot_feeling`,\n"
        "  `slot_event`, or `slot_situation`. Prefer specific, low-level types like\n"
        "  `animal_pet`, `toy_object`, `color`, `snack_food`, `playground_activity`.\n\n"
        "Output STRICT JSON only, no markdown or commentary.\n"
        "Schema:\n"
        "{\n"
        '  \"title\": \"...\",\n'
        '  \"reading_level\": 3,\n'
        '  \"reading_band\": \"Grades 1–2\",\n'
        '  \"target_minutes\": 5,\n'
        '  \"summary\": \"One-sentence parent-facing summary.\",\n'
        '  \"slots\": [\n'
        "    {\n"
        '      \"id\": \"slot_pet\",\n'
        '      \"type\": \"animal_pet\",\n'
        '      \"author_description\": \"A cozy or friendly animal the child might like.\",\n'
        '      \"child_prompt\": \"Can you name an animal you would love to be friends with?\",\n'
        '      \"examples\": [\"puppy\", \"bunny\", \"kitten\"]\n'
        "    }\n"
        "  ],\n"
        '  \"sentences\": [\n'
        "    {\n"
        '      \"id\": \"s1\",\n'
        '      \"text_with_blanks\": \"[[slot_child]] loved to play with [[slot_toy]] in the park.\",\n'
        '      \"slot_ids\": [\"slot_child\", \"slot_toy\"]\n'
        "    }\n"
        "  ]\n"
        "}\n"
    )


def _system_prompt_batch() -> str:
    """
    Variant of the system prompt that asks for multiple distinct templates
    in a single response. The inner template shape is the same as for the
    single-template case, but wrapped in a top-level `templates` array.
    """
    base = _system_prompt()
    # Replace the final schema block with a batch schema description.
    # We rely on the same inner fields; we just describe an outer wrapper.
    return (
        base
        + "\n\n"
        "Now, instead of a single template, generate STRICT JSON with this shape:\n"
        "{\n"
        '  \"templates\": [\n'
        "    {\n"
        '      \"title\": \"...\",\n'
        '      \"reading_level\": 3,\n'
        '      \"reading_band\": \"Grades 1–2\",\n'
        '      \"target_minutes\": 5,\n'
        '      \"summary\": \"One-sentence parent-facing summary.\",\n'
        '      \"slots\": [ ... ],\n'
        '      \"sentences\": [ ... ]\n'
        "    },\n"
        "    { \"title\": \"...\", ... },\n"
        "    { \"title\": \"...\", ... }\n"
        "  ]\n"
        "}\n"
        "Generate exactly the requested number of templates. Make sure each template has a\n"
        "clearly different main situation or setting so that they feel distinct from each other.\n"
    )


def _build_user_payload(level: int) -> Dict[str, Any]:
    """
    Build a minimal payload describing the desired story.
    For now we focus on Level 3, but this is parameterized for future levels.
    """
    if level <= 2:
        band = "K–1"
        target_minutes = 3
    elif level == 3:
        band = "Grades 1–2"
        target_minutes = 5
    else:
        band = "Grades 2–3"
        target_minutes = 6

    return {
        "reading_level": level,
        "reading_band": band,
        "target_minutes": target_minutes,
        "constraints": {
            "max_sentences": 16,
            "min_sentences": 8,
            "max_slots": 8,
            "tone": "warm, curious, gently playful",
            "avoid": ["bullying", "realistic injury", "death"],
        },
    }


def _call_openrouter(
    *,
    api_key: str,
    model: str,
    system: str,
    user_payload: Dict[str, Any],
    temperature: float,
) -> Dict[str, Any]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Mad Libs Story Generator",
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
        "temperature": temperature,
        "max_output_tokens": 1024,
        "usage": {"include": True},
        "user": "madlibs_story_generator",
    }
    data_bytes = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", method="POST"
    )
    for k, v in headers.items():
        req.add_header(k, v)
    req.data = data_bytes

    with urllib.request.urlopen(req, timeout=90) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw)


def _extract_first_json_object(text: str) -> str:
    """
    Extract the first *balanced* JSON object from a string that may contain
    extra commentary before or after the JSON. This is a bit more robust than
    a naive first/last brace slice and mirrors the strategy used in the
    interactive next-sentence demo.
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


def _parse_template(content: str) -> MadLibStoryTemplate:
    """
    Parse the model's JSON content into our dataclasses.
    Tries to be robust to minor deviations (extra text around the JSON).
    """
    extracted = _extract_first_json_object(content)
    data = json.loads(extracted)
    slots = [
        MadLibSlot(
            id=s["id"],
            type=s.get("type", ""),
            author_description=s.get("author_description", ""),
            child_prompt=s.get("child_prompt", ""),
            examples=[str(e) for e in (s.get("examples") or [])],
        )
        for s in data.get("slots", [])
    ]
    sentences = [
        MadLibSentence(
            id=s["id"],
            text_with_blanks=s.get("text_with_blanks", ""),
            slot_ids=[str(x) for x in (s.get("slot_ids") or [])],
        )
        for s in data.get("sentences", [])
    ]
    return MadLibStoryTemplate(
        title=data.get("title", "Untitled Story"),
        reading_level=int(data.get("reading_level", 3)),
        reading_band=data.get("reading_band", ""),
        target_minutes=int(data.get("target_minutes", 5)),
        summary=data.get("summary", ""),
        sentences=sentences,
        slots=slots,
    )


def _parse_templates(content: str) -> List[MadLibStoryTemplate]:
    """
    Parse one or more templates from the model's JSON content.
    Supports either a single template object or an object with
    a `templates` array.
    """
    extracted = _extract_first_json_object(content)
    data = json.loads(extracted)

    # If the model already returned a `templates` array, use it.
    if isinstance(data, dict) and "templates" in data:
        raw_list = data.get("templates") or []
    else:
        # Fallback: treat `data` itself as a single template object.
        raw_list = [data]

    templates: List[MadLibStoryTemplate] = []
    for obj in raw_list:
        slots = [
            MadLibSlot(
                id=s["id"],
                type=s.get("type", ""),
                author_description=s.get("author_description", ""),
                child_prompt=s.get("child_prompt", ""),
                examples=[str(e) for e in (s.get("examples") or [])],
            )
            for s in obj.get("slots", [])
        ]
        sentences = [
            MadLibSentence(
                id=s["id"],
                text_with_blanks=s.get("text_with_blanks", ""),
                slot_ids=[str(x) for x in (s.get("slot_ids") or [])],
            )
            for s in obj.get("sentences", [])
        ]
        templates.append(
            MadLibStoryTemplate(
                title=obj.get("title", "Untitled Story"),
                reading_level=int(obj.get("reading_level", 3)),
                reading_band=obj.get("reading_band", ""),
                target_minutes=int(obj.get("target_minutes", 5)),
                summary=obj.get("summary", ""),
                sentences=sentences,
                slots=slots,
            )
        )
    return templates


def _strip_markdown_fences(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        t = t.lstrip("`")
        if t.lower().startswith("json"):
            t = t[4:]
        if "```" in t:
            t = t.split("```", 1)[0]
    return t.strip()


def generate_madlibs_story(level: int, model: str, temperature: float) -> MadLibStoryTemplate:
    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")

    system = _system_prompt()
    user_payload = _build_user_payload(level)

    print(f"Calling OpenRouter model={model} for Mad Libs story (level={level})...")
    try:
        t0 = time.perf_counter()
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

    t1 = time.perf_counter()
    usage = data.get("usage")
    if usage:
        print(f"Usage: {usage}")
        print(f"Generator latency: {t1 - t0:.2f}s")

    content = data["choices"][0]["message"]["content"]
    text = _strip_markdown_fences(str(content or ""))
    template = _parse_template(text)
    return template


def generate_madlibs_stories_batch(
    level: int, model: str, temperature: float, count: int
) -> List[MadLibStoryTemplate]:
    """
    Generate multiple distinct Mad Libs story templates in a single
    model call. This is primarily used by the evolver to encourage
    within-call diversity.
    """
    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")

    system = _system_prompt_batch()
    user_payload = _build_user_payload(level)
    user_payload["count"] = count

    print(
        f"Calling OpenRouter model={model} for {count} Mad Libs stories "
        f"(level={level})..."
    )
    try:
        t0 = time.perf_counter()
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

    t1 = time.perf_counter()
    usage = data.get("usage")
    if usage:
        print(f"Usage: {usage}")
        print(f"Generator latency (batch): {t1 - t0:.2f}s")

    content = data["choices"][0]["message"]["content"]
    text = _strip_markdown_fences(str(content or ""))
    templates = _parse_templates(text)
    # Be defensive: only return up to the requested count.
    return templates[:count]


def _save_template(
    template: MadLibStoryTemplate,
    meta: Dict[str, Any] | None = None,
) -> Path:
    out_dir = Path(__file__).parent / "generated_madlibs_stories"
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    json_path = out_dir / f"madlib_story_level{template.reading_level}_{ts}.json"
    payload: Dict[str, Any] = {"template": asdict(template)}
    if meta:
        payload["meta"] = meta
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    txt_path = out_dir / f"madlib_story_level{template.reading_level}_{ts}.txt"
    with txt_path.open("w", encoding="utf-8") as f:
        f.write(f"Title: {template.title}\n")
        f.write(f"Level: {template.reading_level} ({template.reading_band})\n")
        f.write(f"Target minutes: {template.target_minutes}\n")
        f.write(f"Summary: {template.summary}\n\n")
        f.write("Slots:\n")
        for slot in template.slots:
            f.write(
                f"- {slot.id} ({slot.type}): {slot.author_description}\n"
                f"  Child prompt: {slot.child_prompt}\n"
                f"  Examples: {', '.join(slot.examples)}\n"
            )
        f.write("\nStory template:\n")
        for s in template.sentences:
            f.write(f"{s.id}: {s.text_with_blanks}\n")

    print(f"Saved Mad Libs template JSON to: {json_path}")
    print(f"Saved human-readable template to: {txt_path}")
    return json_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a Mad Libs–style story template for Xen Words."
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
        help="OpenRouter model id to use (default: inception/mercury).",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=None,
        help=(
            "Sampling temperature for generation. "
            "If not provided, uses generator_temperature from madlibs_dg_config.json."
        ),
    )
    args = parser.parse_args()

    sampling_cfg = load_sampling_config()
    temperature = args.temperature
    if temperature is None:
        temperature = float(sampling_cfg.get("generator_temperature", 0.9))

    template = generate_madlibs_story(
        level=args.level,
        model=args.model,
        temperature=temperature,
    )
    _save_template(
        template,
        meta={
            "generator_model": args.model,
            "generator_prompt_version": GENERATOR_PROMPT_VERSION,
            "generator_temperature": temperature,
        },
    )


if __name__ == "__main__":
    main()


