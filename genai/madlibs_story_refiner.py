"""
Mad Libs story refiner – one-step Darwin/Goedel-style refinement.

Takes an existing Mad Libs story template JSON (as produced by
`madlibs_story_generator.py`), asks an LLM to refine it while preserving:
- reading level,
- overall structure and slot ids/types,
- Mad Libs usability (concrete, easy-to-fill blanks),
and tries to improve:
- story arc (clearer problem + resolution),
- character engagement,
- emotional warmth and curiosity hooks.

It then runs the same LLM judge used in `madlibs_story_evolver.py` to score
the refined template, and saves it alongside the original.

Usage (from repo root):
    cd genai
    python madlibs_story_refiner.py \
      --input generated_madlibs_stories/madlib_story_level3_20251202_115950.json \
      --model inception/mercury \
      --judge-model inception/mercury
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

import urllib.request
import urllib.error

from madlibs_story_generator import (
    MadLibStoryTemplate,
    MadLibSentence,
    MadLibSlot,
    load_env,
    load_sampling_config,
)
from madlibs_story_evolver import _call_judge


def load_template(path: Path) -> MadLibStoryTemplate:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    # If this is a comparison wrapper (with original/refined), prefer the refined
    # template for further iterations.
    if "refined" in data and isinstance(data["refined"], dict):
        data = data["refined"]
    # If this is a generator/evolver wrapper, unwrap the inner template.
    if "template" in data and isinstance(data["template"], dict):
        data = data["template"]
    sentences = [
        MadLibSentence(
            id=s["id"],
            text_with_blanks=s.get("text_with_blanks", ""),
            slot_ids=[str(x) for x in (s.get("slot_ids") or [])],
        )
        for s in data.get("sentences", [])
    ]
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
    return MadLibStoryTemplate(
        title=data.get("title", "Untitled Story"),
        reading_level=int(data.get("reading_level", 3)),
        reading_band=data.get("reading_band", ""),
        target_minutes=int(data.get("target_minutes", 5)),
        summary=data.get("summary", ""),
        sentences=sentences,
        slots=slots,
    )


def _refine_system_prompt() -> str:
    return (
        "You are revising a Mad Libs–style children's story template.\n"
        "The template is already roughly appropriate for reading level 3 (Grades 1–2)\n"
        "and uses concrete blanks (toys, animals, colors, snacks, activities).\n\n"
        "Your job is to create a NEW version of this template that:\n"
        "- Keeps the same overall format and JSON schema.\n"
        "- Preserves all slot ids and slot types exactly (no renaming, no new ids).\n"
        "- Keeps reading_level and reading_band consistent.\n"
        "- Keeps the story roughly the same length (do not add or remove more than 2 sentences).\n"
        "- Improves story qualities:\n"
        "  * Clearer beginning / middle / end.\n"
        "  * A small but meaningful problem or question.\n"
        "  * A gently satisfying resolution.\n"
        "  * Stronger sense of character feeling and growth, without becoming heavy.\n"
        "  * A bit more curiosity or surprise, while staying cozy and safe.\n"
        "- Keeps blanks easy for kids to fill; they should stay concrete nouns or very\n"
        "  simple activities. Do not turn blanks into abstract ideas or long phrases.\n\n"
        "Output STRICT JSON only, no commentary or markdown fences. Use this schema:\n"
        "{\n"
        '  \"title\": \"...\",\n'
        '  \"reading_level\": 3,\n'
        '  \"reading_band\": \"Grades 1–2\",\n'
        '  \"target_minutes\": 5,\n'
        '  \"summary\": \"One-sentence parent-facing summary.\",\n'
        '  \"slots\": [ ... same slot ids and types as input ... ],\n'
        '  \"sentences\": [\n'
        "    {\n"
        '      \"id\": \"s1\",\n'
        '      \"text_with_blanks\": \"...\",\n'
        '      \"slot_ids\": [\"slot_child\", \"slot_toy\"]\n'
        "    }\n"
        "  ]\n"
        "}\n"
    )


def _call_refiner(
    *,
    api_key: str,
    model: str,
    original: MadLibStoryTemplate,
    temperature: float,
) -> MadLibStoryTemplate:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Mad Libs Story Refiner",
    }
    system = _refine_system_prompt()
    user_payload: Dict[str, Any] = {
        "template": asdict(original),
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
        "user": "madlibs_story_refiner",
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
        data = json.loads(raw)
    content = data["choices"][0]["message"]["content"]
    text = str(content or "").strip()
    if text.startswith("```"):
        text = text.lstrip("`")
        if text.lower().startswith("json"):
            text = text[4:]
        if "```" in text:
            text = text.split("```", 1)[0]
        text = text.strip()
    parsed = json.loads(text)

    refined = MadLibStoryTemplate(
        title=parsed.get("title", original.title),
        reading_level=int(parsed.get("reading_level", original.reading_level)),
        reading_band=parsed.get("reading_band", original.reading_band),
        target_minutes=int(parsed.get("target_minutes", original.target_minutes)),
        summary=parsed.get("summary", original.summary),
        sentences=[
            MadLibSentence(
                id=s["id"],
                text_with_blanks=s.get("text_with_blanks", ""),
                slot_ids=[str(x) for x in (s.get("slot_ids") or [])],
            )
            for s in parsed.get("sentences", [])
        ],
        slots=[
            MadLibSlot(
                id=s["id"],
                type=s.get("type", ""),
                author_description=s.get("author_description", ""),
                child_prompt=s.get("child_prompt", ""),
                examples=[str(e) for e in (s.get("examples") or [])],
            )
            for s in parsed.get("slots", [])
        ],
    )
    return refined


def _save_refined(
    original_path: Path,
    original: MadLibStoryTemplate,
    refined: MadLibStoryTemplate,
    judge_scores: Dict[str, float],
) -> Path:
    out_dir = original_path.parent
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = original_path.stem + "_refined_" + ts

    json_path = out_dir / f"{stem}.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "original": asdict(original),
                "refined": asdict(refined),
                "judge_scores": judge_scores,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    txt_path = out_dir / f"{stem}.txt"
    with txt_path.open("w", encoding="utf-8") as f:
        f.write(f"Original title: {original.title}\n")
        f.write(f"Refined title:  {refined.title}\n")
        f.write(f"Reading level:   {refined.reading_level} ({refined.reading_band})\n")
        f.write(f"Target minutes:  {refined.target_minutes}\n")
        f.write(f"Summary (refined): {refined.summary}\n\n")
        f.write("Judge scores:\n")
        for k, v in judge_scores.items():
            f.write(f"- {k}: {v:.2f}\n")
        f.write("\n--- Original template ---\n")
        for s in original.sentences:
            f.write(f"{s.id}: {s.text_with_blanks}\n")
        f.write("\n--- Refined template ---\n")
        for s in refined.sentences:
            f.write(f"{s.id}: {s.text_with_blanks}\n")

    print(f"Saved refined comparison JSON to: {json_path}")
    print(f"Saved refined comparison TXT to:  {txt_path}")
    return txt_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Refine a single Mad Libs story template using an LLM."
    )
    parser.add_argument(
        "--input",
        type=str,
        required=True,
        help="Path to the original template JSON file.",
    )
    parser.add_argument(
        "--model",
        type=str,
        default="inception/mercury",
        help="OpenRouter model id to use for refinement (default: inception/mercury).",
    )
    parser.add_argument(
        "--judge-model",
        type=str,
        default="",
        help="Optional model id to use for judging (default: same as --model).",
    )
    args = parser.parse_args()

    env = load_env()
    sampling_cfg = load_sampling_config()
    refiner_temperature = float(sampling_cfg.get("refiner_temperature", 0.4))
    judge_temperature = float(sampling_cfg.get("judge_temperature", 0.1))
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")

    input_path = Path(args.input)
    original = load_template(input_path)
    print(f"Loaded original template: {original.title}")

    refined = _call_refiner(
        api_key=api_key,
        model=args.model,
        original=original,
        temperature=refiner_temperature,
    )
    print(f"Refined template title: {refined.title}")

    judge_model = args.judge_model or args.model
    judge_scores = _call_judge(
        api_key=api_key,
        model=judge_model,
        template=refined,
        temperature=judge_temperature,
    )
    print(f"Judge scores: {judge_scores}")

    _save_refined(input_path, original, refined, judge_scores)


if __name__ == "__main__":
    main()


