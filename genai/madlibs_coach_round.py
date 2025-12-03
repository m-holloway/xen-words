"""
One-shot DG coaching experiment for Mad Libs story templates.

Flow (library-building mode):
- Generate a small cohort of Level 3 Mad Libs templates using Mercury in batch.
- Judge each candidate with Gemini 2.5 Flash (same axes as evolver).
- Call a "coach" model (also Gemini 2.5 Flash for now) with the cohort + scores to get:
  - cohort_summary (common strengths/weaknesses, patterns to reduce/explore)
  - per_story_feedback (next_round_goals for the top candidates)
- Save all artifacts to disk so we can later wire the feedback into a refiner.

This script does NOT yet perform the refinement step; it focuses on
producing high-quality coaching feedback from a whole cohort.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

import urllib.request
import urllib.error

from madlibs_story_generator import (
    MadLibStoryTemplate,
    generate_madlibs_stories_batch,
    load_env,
    load_sampling_config,
)
from madlibs_story_evolver import _call_judge


def _sample_sentences(t: MadLibStoryTemplate, max_sentences: int = 4) -> List[str]:
    return [s.text_with_blanks for s in t.sentences[:max_sentences]]


def _coach_system_prompt() -> str:
    return (
        "You are a high-taste children's story coach and critic.\n"
        "You are helping an AI team build a curated library of Level 3 (Grades 1–2)\n"
        "Mad Libs–style story templates.\n\n"
        "You are given a small COHORT of candidate stories. For each story you see:\n"
        "- title, summary, a few sample sentences,\n"
        "- numeric scores from a separate judge model (overall, story_arc, novelty,\n"
        "  memorable_moment, show_vs_tell, character_depth, kid_retellability, etc.).\n\n"
        "Your job is NOT to re-score the stories, but to:\n"
        "1) Summarise what this cohort is doing well, and where it is weak.\n"
        "2) Identify any overused patterns or motifs in THIS cohort.\n"
        "3) Give targeted, constructive coaching feedback for the strongest stories so\n"
        "   that a refiner model could produce even better second-round versions.\n\n"
        "Important:\n"
        "- Imagine you are a candid, expert panelist on a creative reality show.\n"
        "- Be honest but kind; the audience is other models and human reviewers.\n"
        "- Avoid generic advice like \"make it more interesting\"; instead give 2–3\n"
        "  concrete next steps per standout story.\n\n"
        "Respond with STRICT JSON only, no markdown, using this schema:\n"
        "{\n"
        "  \"cohort_summary\": {\n"
        "    \"common_strengths\": [\"...\"],\n"
        "    \"common_weaknesses\": [\"...\"],\n"
        "    \"patterns_to_reduce\": [\"...\"],\n"
        "    \"patterns_to_explore\": [\"...\"]\n"
        "  },\n"
        "  \"per_story_feedback\": [\n"
        "    {\n"
        "      \"story_id\": \"c1\",\n"
        "      \"is_standout\": true,\n"
        "      \"headline\": \"Short one-line coach summary.\",\n"
        "      \"strengths\": [\"...\"],\n"
        "      \"weaknesses\": [\"...\"],\n"
        "      \"next_round_goals\": [\"concrete, refiner-ready goals\"]\n"
        "    }\n"
        "  ]\n"
        "}\n"
    )


def _call_coach(*, api_key: str, model: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Mad Libs Story Coach",
    }
    system = _coach_system_prompt()
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
                "content": json.dumps(payload, ensure_ascii=False),
                "cache_control": {"type": "ephemeral"},
            },
        ],
        "temperature": 0.4,
        "max_output_tokens": 768,
        "usage": {"include": True},
        "user": "madlibs_story_coach",
    }
    data_bytes = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", method="POST"
    )
    for k, v in headers.items():
        req.add_header(k, v)
    req.data = data_bytes

    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            raw = resp.read().decode("utf-8")
            data = json.loads(raw)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenRouter HTTPError {e.code}: {body[:400]}") from e
    except Exception as e:
        raise SystemExit(f"OpenRouter request to coach failed: {e}") from e

    usage = data.get("usage")
    if usage:
        print(f"Coach usage: {usage}")
    content = data["choices"][0]["message"]["content"]
    text = str(content or "").strip()
    # No markdown expected, but be conservative.
    if text.startswith("```"):
        text = text.lstrip("`")
        if text.lower().startswith("json"):
            text = text[4:]
        if "```" in text:
            text = text.split("```", 1)[0]
        text = text.strip()
    return json.loads(text)


def run_coach_round(
    level: int = 3,
    generator_model: str = "inception/mercury",
    judge_model: str = "google/gemini-2.5-flash",
    coach_model: str = "google/gemini-2.5-flash",
    cohort_size: int = 6,
) -> None:
    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")
    sampling = load_sampling_config()
    gen_temp = float(
        sampling.get(
            "evolver_generator_temperature", sampling.get("generator_temperature", 1.0)
        )
    )

    # 1) Generate cohort in one or two batches via existing batch helper.
    templates = generate_madlibs_stories_batch(
        level=level, model=generator_model, temperature=gen_temp, count=cohort_size
    )

    # 2) Judge each candidate.
    judged: List[Dict[str, Any]] = []
    for idx, tmpl in enumerate(templates, start=1):
        print(f"\n=== Judge candidate c{idx}: '{tmpl.title}' ===")
        scores = _call_judge(
            api_key=api_key,
            model=judge_model,
            template=tmpl,
            temperature=float(sampling.get("judge_temperature", 0.1)),
        )
        print(f"  Scores: {scores}")
        judged.append(
            {
                "id": f"c{idx}",
                "template": tmpl,
                "scores": scores,
            }
        )

    # 3) Build coaching payload.
    # Keep everything small: title, summary, 3–4 sample sentences, numeric scores.
    cohort_payload = {
        "level": level,
        "generator_model": generator_model,
        "judge_model": judge_model,
        "candidates": [
            {
                "story_id": j["id"],
                "title": j["template"].title,
                "summary": j["template"].summary,
                "sample_sentences": _sample_sentences(j["template"], max_sentences=4),
                "scores": j["scores"],
            }
            for j in judged
        ],
    }

    # 4) Call coach.
    print("\n=== Calling coach model for cohort feedback ===")
    coach_feedback = _call_coach(
        api_key=api_key, model=coach_model, payload=cohort_payload
    )

    # 5) Persist everything for later refinement experiments.
    out_dir = Path(__file__).parent / "generated_madlibs_stories"
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = out_dir / f"coach_round_level{level}_{ts}.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "config": {
                    "level": level,
                    "generator_model": generator_model,
                    "judge_model": judge_model,
                    "coach_model": coach_model,
                    "cohort_size": cohort_size,
                },
                "candidates": [
                    {
                        "id": j["id"],
                        "template": asdict(j["template"]),
                        "scores": j["scores"],
                    }
                    for j in judged
                ],
                "coach_feedback": coach_feedback,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
    print(f"Saved coach round JSON to: {json_path}")

    # Also print a short human-readable summary for quick inspection.
    print("\n=== Coach cohort summary ===")
    print(json.dumps(coach_feedback.get("cohort_summary", {}), indent=2))
    print("\n=== Coach per-story headlines ===")
    for item in coach_feedback.get("per_story_feedback", []):
        sid = item.get("story_id")
        headline = item.get("headline", "")
        print(f"- {sid}: {headline}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Run a single coaching round for Mad Libs templates."
    )
    parser.add_argument(
        "--level",
        type=int,
        default=3,
        help="Reading level (default: 3).",
    )
    parser.add_argument(
        "--cohort-size",
        type=int,
        default=6,
        help="Number of candidates to generate and coach in this round (default: 6).",
    )
    parser.add_argument(
        "--generator-model",
        type=str,
        default="inception/mercury",
        help="OpenRouter model id for generation (default: inception/mercury).",
    )
    parser.add_argument(
        "--judge-model",
        type=str,
        default="google/gemini-2.5-flash",
        help="OpenRouter model id for judging (default: google/gemini-2.5-flash).",
    )
    parser.add_argument(
        "--coach-model",
        type=str,
        default="google/gemini-2.5-flash",
        help="OpenRouter model id for coaching (default: google/gemini-2.5-flash).",
    )
    args = parser.parse_args()

    run_coach_round(
        level=args.level,
        generator_model=args.generator_model,
        judge_model=args.judge_model,
        coach_model=args.coach_model,
        cohort_size=args.cohort_size,
    )


