"""
Refine a single Mad Libs story template using cohort coaching feedback.

This script ties together:
- A saved coach round JSON (from madlibs_coach_round.py),
- Per-story feedback (next_round_goals, strengths/weaknesses),
- A refiner call (Mercury) that explicitly responds to that feedback,
- And fresh judge scores (Gemini 2.5 Flash and optionally Gemini 3 Pro).

It writes a comparison JSON into generated_madlibs_stories/ so we can
compare original vs coached-refined versions and their scores.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

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


def _coach_refine_system_prompt() -> str:
    return (
        "You are revising a Mad Libs–style children's story template based on\n"
        "specific coaching feedback from a high-taste critic.\n\n"
        "Input:\n"
        "- `template`: the current Level 3 story template (title, summary, slots, sentences).\n"
        "- `feedback`: critic notes including strengths, weaknesses, and `next_round_goals`.\n"
        "- `cohort_summary`: optional notes about common patterns to reduce or explore.\n\n"
        "Your job:\n"
        "- Preserve what is already working well in the template (tone, basic arc, safety).\n"
        "- Make concrete changes that directly respond to the critic's `next_round_goals`.\n"
        "- Keep reading_level, reading_band, and target_minutes consistent (Level 3).\n"
        "- Keep the overall length similar (do not add or remove more than ~2 sentences).\n"
        "- Preserve all slot ids and slot types; you may rephrase slot descriptions/prompts\n"
        "  slightly if that helps, but do NOT add or remove slots.\n"
        "- Keep the story cozy, non-scary, and appropriate for early readers.\n\n"
        "Guidance:\n"
        "- Treat `next_round_goals` as the main source of change. If a goal says to clarify\n"
        "  how a problem works, or to add a more vivid image, or to replace a generic\n"
        "  phrase with an action, do so concretely.\n"
        "- You may rephrase sentences, adjust the problem or its resolution slightly, and\n"
        "  add small details that deepen character feelings or memorable moments.\n"
        "- Do NOT introduce dark themes, real danger, or abstract/wordy language.\n\n"
        "Output STRICT JSON only, no commentary or markdown. Use this schema:\n"
        "{\n"
        "  \"title\": \"...\",\n"
        "  \"reading_level\": 3,\n"
        "  \"reading_band\": \"Grades 1–2\",\n"
        "  \"target_minutes\": 5,\n"
        "  \"summary\": \"One-sentence parent-facing summary.\",\n"
        "  \"slots\": [ ... same slot ids and types as input ... ],\n"
        "  \"sentences\": [\n"
        "    { \"id\": \"s1\", \"text_with_blanks\": \"...\", \"slot_ids\": [\"slot_child\", ...] },\n"
        "    ...\n"
        "  ]\n"
        "}\n\n"
        "Special cases (refinement modes):\n"
        "- The `feedback` object includes a boolean field `is_standout` and may include a\n"
        "  `refinement_mode` field (e.g., 'polish' or 'reboot') and `exemplar_stories`.\n"
        "- If `refinement_mode` is 'polish' (or `is_standout` is true), prefer gentle,\n"
        "  targeted improvements that keep the core situation, setting, and problem\n"
        "  intact while sharpening specific moments.\n"
        "- If `refinement_mode` is 'reboot' (non-standout story), you are allowed to\n"
        "  start a fresh take on the story while learning from the feedback and\n"
        "  exemplar stories:\n"
        "  * You may change the main situation, setting, and problem so that the story\n"
        "    no longer relies purely on the overused patterns mentioned in the coach's\n"
        "    weaknesses or in `patterns_to_reduce`.\n"
        "  * You may add or remove sentences more freely (staying within a short\n"
        "    8–14 sentence length typical for a Level 3 story) and adjust the slots to\n"
        "    better fit the new idea, as long as they remain concrete, kid-friendly\n"
        "    Mad Libs blanks (animals, toys, colors, foods, simple activities, places).\n"
        "  * Use `exemplar_stories` and their `coach_strengths` as inspiration for what\n"
        "    makes a story stand out (e.g., a clear mini-puzzle, a strong magical image,\n"
        "    or a distinctive emotional beat), but do NOT copy them; invent a new story.\n"
    )


def _call_coach_refiner(
    *,
    api_key: str,
    model: str,
    original: MadLibStoryTemplate,
    feedback: Dict[str, Any],
) -> MadLibStoryTemplate:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Mad Libs Story Coach Refiner",
    }
    system = _coach_refine_system_prompt()
    user_payload: Dict[str, Any] = {
        "template": asdict(original),
        "feedback": feedback,
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
        "temperature": 0.4,
        "max_output_tokens": 1024,
        "usage": {"include": True},
        "user": "madlibs_story_coach_refiner",
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
        raise SystemExit(f"OpenRouter request to refiner failed: {e}") from e

    usage = data.get("usage")
    if usage:
        print(f"Refiner usage: {usage}")
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


def _template_from_candidate(obj: Dict[str, Any]) -> MadLibStoryTemplate:
    data = obj["template"]
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


def run_refine_with_coach(
    coach_round_path: Path,
    story_id: str,
    refiner_model: str = "inception/mercury",
    judge_model_main: str = "google/gemini-2.5-flash",
    judge_model_final: str | None = "google/gemini-3-pro-preview",
) -> None:
    data = json.loads(coach_round_path.read_text(encoding="utf-8"))
    candidates = data.get("candidates", [])
    coach_section = data.get("coach_feedback", {}) or {}
    feedback_list = coach_section.get("per_story_feedback", [])
    cohort_summary = coach_section.get("cohort_summary") or {}

    candidate_obj = next((c for c in candidates if c.get("id") == story_id), None)
    feedback_obj = next(
        (f for f in feedback_list if f.get("story_id") == story_id), None
    )
    if not candidate_obj or not feedback_obj:
        raise SystemExit(f"Could not find candidate or feedback for story_id={story_id}")

    original = _template_from_candidate(candidate_obj)
    original_scores = candidate_obj.get("scores", {})

    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env or environment")
    sampling = load_sampling_config()

    print(f"Loaded original story '{original.title}' with id={story_id}")
    print(f"Original scores (main judge): {original_scores}")

    # Enrich feedback for the refiner with refinement_mode, direction hints,
    # and a small set of exemplar stories from the same cohort.
    is_standout = bool(feedback_obj.get("is_standout"))
    # For now we treat all non-standouts as candidates for a full reboot
    # rather than gentle line edits.
    refinement_mode = "polish" if is_standout else "reboot"
    # Build a simple, human-readable direction hint string for non-standouts.
    direction_hint = ""
    if not is_standout:
        headline = feedback_obj.get("headline", "")
        weaknesses = feedback_obj.get("weaknesses") or []
        patterns_to_reduce = cohort_summary.get("patterns_to_reduce") or []
        direction_hint = (
            "This story was not a standout in the cohort. Headline feedback: "
            f"{headline}. Key weaknesses: "
            + "; ".join(weaknesses)
        )
        if patterns_to_reduce:
            direction_hint += (
                ". The coach also suggested reducing these cohort-wide patterns: "
                + "; ".join(patterns_to_reduce)
            )

    refiner_feedback: Dict[str, Any] = dict(feedback_obj)
    refiner_feedback["refinement_mode"] = refinement_mode
    if direction_hint:
        refiner_feedback["direction_hint"] = direction_hint

    # Build a small exemplar set from other standout stories in the same cohort
    # so the refiner can see what the coach liked.
    exemplars: List[Dict[str, Any]] = []
    # Map story_id -> candidate for quick lookup
    cand_by_id = {c.get("id"): c for c in candidates}
    for fb in feedback_list:
        sid = fb.get("story_id")
        if not sid or sid == story_id:
            continue
        if not fb.get("is_standout"):
            continue
        cand = cand_by_id.get(sid)
        if not cand:
            continue
        tmpl = _template_from_candidate(cand)
        exemplars.append(
            {
                "story_id": sid,
                "title": tmpl.title,
                "summary": tmpl.summary,
                "sample_sentences": [
                    s.text_with_blanks for s in tmpl.sentences[:4]
                ],
                "coach_strengths": fb.get("strengths") or [],
            }
        )
    if exemplars:
        refiner_feedback["exemplar_stories"] = exemplars
    # 1) Refine using coaching feedback.
    refined = _call_coach_refiner(
        api_key=api_key,
        model=refiner_model,
        original=original,
        feedback=refiner_feedback,
    )
    print(f"Refined story title: {refined.title}")

    # 2) Judge refined story with main judge (Flash).
    refined_scores_main = _call_judge(
        api_key=api_key,
        model=judge_model_main,
        template=refined,
        temperature=float(sampling.get("judge_temperature", 0.1)),
    )
    print(f"Refined scores (main judge): {refined_scores_main}")

    # 3) Optionally judge refined story with final judge (Gemini 3 Pro).
    refined_scores_final: Dict[str, float] | None = None
    if judge_model_final:
        try:
            refined_scores_final = _call_judge(
                api_key=api_key,
                model=judge_model_final,
                template=refined,
                temperature=float(sampling.get("judge_temperature", 0.1)),
            )
            print(f"Refined scores (final judge): {refined_scores_final}")
        except Exception as e:
            print(f"Final judge failed: {e}")

    # 4) Persist comparison.
    out_dir = Path(__file__).parent / "generated_madlibs_stories"
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"{coach_round_path.stem}_{story_id}_coached_refined_{ts}"
    json_path = out_dir / f"{stem}.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "coach_round_path": str(coach_round_path),
                "story_id": story_id,
                "original": asdict(original),
                "original_scores_main": original_scores,
                "feedback": feedback_obj,
                "refined": asdict(refined),
                "refined_scores_main": refined_scores_main,
                "refined_scores_final": refined_scores_final,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
    print(f"Saved coached refinement comparison JSON to: {json_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Refine a single Mad Libs story using cohort coaching feedback."
    )
    parser.add_argument(
        "--coach-round",
        type=str,
        required=True,
        help="Path to a coach_round_level*.json file.",
    )
    parser.add_argument(
        "--story-id",
        type=str,
        required=True,
        help="Story id within that coach round (e.g. c2).",
    )
    args = parser.parse_args()
    run_refine_with_coach(
        coach_round_path=Path(args.coach_round),
        story_id=args.story_id,
    )


if __name__ == "__main__":
    main()


