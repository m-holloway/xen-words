"""
Darwin/Goedel-style Mad Libs story evolver.

This script builds on `madlibs_story_generator.py` to:
- Generate multiple candidate Mad Libs story templates (using a fast model
  like inception/mercury).
- Score each template with:
  - Simple **heuristics** (sentence count, slot quality, blank density).
  - An optional **LLM-based judge** that rates story arc, engagement, and
    Mad Libs usability.
- Print a ranked summary so we can quickly inspect the strongest candidates
  and then curate them for inclusion in the app.

Usage (from repo root):
    cd genai
    python madlibs_story_evolver.py --level 3 --model inception/mercury --count 5
    # Optionally specify a separate judge model (defaults to generator model):
    python madlibs_story_evolver.py --level 3 --model inception/mercury --judge-model inception/mercury --count 5
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from typing import Dict, List, Optional
import time

from madlibs_story_generator import (
    MadLibStoryTemplate,
    generate_madlibs_story,
    generate_madlibs_stories_batch,
    _save_template,
    load_env,
    load_sampling_config,
    GENERATOR_PROMPT_VERSION,
)

import json
import urllib.request
import urllib.error

@dataclass
class ScoredTemplate:
    template: MadLibStoryTemplate
    score: float
    details: Dict[str, float]
    judge_scores: Optional[Dict[str, float]] = None


def _motif_key(t: MadLibStoryTemplate) -> str:
    """
    Very rough motif fingerprint based on title keywords.
    Used to nudge ranking toward within-population novelty:
    if several stories share the same coarse motif key, we
    slightly down-weight the later ones.
    """
    title = (t.title or "").lower()
    tokens = [w.strip(".,!?\"'") for w in title.split()]
    stop = {"the", "a", "an", "and", "of", "in", "at", "on"}
    keywords = [w for w in tokens if w and w not in stop]
    # Use up to first two meaningful words as the motif key.
    if not keywords:
        return title.strip()
    return " ".join(keywords[:2])


def _score_template(t: MadLibStoryTemplate) -> ScoredTemplate:
    """
    Crude, explainable scoring for now:
    - Base score from sentence and slot count in a reasonable range.
    - Penalties for broad/abstract slot types (we want concrete, easy blanks).
    - Penalties for sentences with too many blanks.
    """
    num_sentences = len(t.sentences)
    num_slots = len(t.slots)

    # Base score: prefer 8–14 sentences, but allow 6–18.
    if num_sentences < 6 or num_sentences > 18:
        base = -5.0
    else:
        # Ideal band gets positive base points.
        if 8 <= num_sentences <= 14:
            base = 5.0
        else:
            base = 2.0

    # Slot-related factors
    abstract_penalty = 0.0
    bad_slot_types = ("problem", "feeling", "event", "situation", "conflict")
    for slot in t.slots:
        slot_type_lower = slot.type.lower()
        if any(bad in slot_type_lower for bad in bad_slot_types):
            abstract_penalty += 2.0

    # Penalty for too many slots overall (story becomes too fragmented).
    slot_penalty = 0.0
    if num_slots > 10:
        slot_penalty += (num_slots - 10) * 0.5

    # Per-sentence blank density.
    density_penalty = 0.0
    max_blanks_per_sentence = 2
    for s in t.sentences:
        if len(s.slot_ids) > max_blanks_per_sentence:
            density_penalty += (len(s.slot_ids) - max_blanks_per_sentence) * 0.5

    # Aggregate score.
    score = base - abstract_penalty - slot_penalty - density_penalty
    details = {
        "base": base,
        "abstract_penalty": abstract_penalty,
        "slot_penalty": slot_penalty,
        "density_penalty": density_penalty,
        "num_sentences": float(num_sentences),
        "num_slots": float(num_slots),
    }
    return ScoredTemplate(template=t, score=score, details=details)


def _judge_system_prompt() -> str:
    return (
        "You are an expert children's story designer and critic.\n"
        "You are given a Mad Libs–style story template with:\n"
        "- title, summary, reading level\n"
        "- sentences (some containing [[slot_*]] blanks)\n"
        "- slot definitions (type + child-facing prompts)\n\n"
        "Judge the template on these axes (0.0–1.0 each):\n"
        "- story_arc: clear beginning, middle, and end with a gentle problem and resolution.\n"
        "- character_engagement: how much a child is likely to care about the main character(s).\n"
        "- emotional_warmth: cozy, kind, non-scary tone.\n"
        "- curiosity_hooks: sense of wonder or intrigue that keeps a child wanting the next page.\n"
        "- madlibs_usability: blanks are concrete and easy for children to fill (toys, animals,\n"
        "  colors, foods, simple activities), and the sentences remain natural when filled.\n"
        "- reading_level_fit: appropriate difficulty for a Level 3 reader (Grades 1–2).\n"
        "- novelty: how fresh and non-generic the story feels compared to very common picture-book\n"
        "  patterns (plain lost balloon/kite/toy in a park with a simple snack at the end).\n"
        "  Familiar arcs are allowed, but reward them more when there is a clearly distinctive\n"
        "  detail, image, or emotional beat.\n"
        "- memorable_moment: presence of at least one image or beat a child is likely to retell\n"
        "  later in their own words (for example, a toy that hums and lights up the playground,\n"
        "  or a kite that sings when someone is kind).\n"
        "- show_vs_tell: does the story mostly show feelings and lessons through actions\n"
        "  instead of stating morals directly?\n"
        "- character_depth: presence of a small but real inner decision or feeling shift\n"
        "  for the child character.\n"
        "- kid_retellability: how easy it would be for a 6–8 year old to retell this story in\n"
        "  2–3 simple sentences, naming the main character and one special thing that happened.\n\n"
        "When you think about the scores, imagine whether this template would belong in a curated\n"
        "library of strong stories for this age:\n"
        "- overall ≈ 0.9–1.0: exceptional; you would strongly recommend it.\n"
        "- overall ≈ 0.7–0.8: solid and warm with at least one distinctive, retellable moment.\n"
        "- overall ≈ 0.4–0.6: structurally fine but fairly generic or forgettable.\n"
        "- overall < 0.4: weak, confusing, or not a good fit.\n\n"
        "Respond with STRICT JSON only:\n"
        "{\n"
        '  \"scores\": {\n'
        '    \"overall\": 0.0,\n'
        '    \"story_arc\": 0.0,\n'
        '    \"character_engagement\": 0.0,\n'
        '    \"emotional_warmth\": 0.0,\n'
        '    \"curiosity_hooks\": 0.0,\n'
        '    \"madlibs_usability\": 0.0,\n'
        '    \"reading_level_fit\": 0.0,\n'
        '    \"novelty\": 0.0,\n'
        '    \"memorable_moment\": 0.0,\n'
        '    \"show_vs_tell\": 0.0,\n'
        '    \"character_depth\": 0.0,\n'
        '    \"kid_retellability\": 0.0\n'
        "  },\n"
        '  \"notes\": \"Short natural-language feedback for the author.\"\n'
        "}\n"
    )


def _call_judge(
    *,
    api_key: str,
    model: str,
    template: MadLibStoryTemplate,
    temperature: float,
) -> Dict[str, float]:
    """
    Ask a judge model to rate a single template.
    We keep this lightweight: one call per elite candidate.
    """
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Mad Libs Story Judge",
    }
    system = _judge_system_prompt()
    user_payload = {
        "title": template.title,
        "reading_level": template.reading_level,
        "reading_band": template.reading_band,
        "summary": template.summary,
        "sentences": [
            {
                "id": s.id,
                "text_with_blanks": s.text_with_blanks,
                "slot_ids": s.slot_ids,
            }
            for s in template.sentences
        ],
        "slots": [
            {
                "id": slot.id,
                "type": slot.type,
                "author_description": slot.author_description,
                "child_prompt": slot.child_prompt,
                "examples": slot.examples,
            }
            for slot in template.slots
        ],
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
        "max_output_tokens": 512,
        "usage": {"include": True},
        "user": "madlibs_story_judge",
    }
    data_bytes = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", method="POST"
    )
    for k, v in headers.items():
        req.add_header(k, v)
    req.data = data_bytes

    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read().decode("utf-8")
        data = json.loads(raw)
    t1 = time.perf_counter()
    usage = data.get("usage")
    if usage:
        print(f"  Judge usage ({model}): {usage}")
        print(f"  Judge latency ({model}): {t1 - t0:.2f}s")
    content = data["choices"][0]["message"]["content"]
    # No markdown expected, but be conservative.
    text = str(content or "").strip()
    if text.startswith("```"):
        text = text.lstrip("`")
        if text.lower().startswith("json"):
            text = text[4:]
        if "```" in text:
            text = text.split("```", 1)[0]
        text = text.strip()
    parsed = json.loads(text)
    scores = parsed.get("scores") or {}
    # Coerce to floats where possible.
    return {k: float(scores.get(k, 0.0)) for k in scores.keys()}


def evolve(
    level: int,
    model: str,
    count: int,
    judge_model: Optional[str] = None,
) -> List[ScoredTemplate]:
    results: List[ScoredTemplate] = []
    env = load_env()
    sampling_cfg = load_sampling_config()
    gen_temperature = float(
        sampling_cfg.get("evolver_generator_temperature", sampling_cfg.get("generator_temperature", 0.9))
    )
    judge_temperature = float(sampling_cfg.get("judge_temperature", 0.1))
    api_key = env.get("OPENROUTER_API_KEY", "").strip() if judge_model else ""
    generated = 0
    batch_size = 3  # number of templates to ask Mercury for in a single call
    while generated < count:
        remaining = count - generated
        this_batch = min(batch_size, remaining)
        print(
            f"\n=== Generating candidates {generated + 1}"
            f"–{generated + this_batch}/{count} (batch) ==="
        )
        templates = generate_madlibs_stories_batch(
            level=level, model=model, temperature=gen_temperature, count=this_batch
        )
        for tmpl in templates:
            generated += 1
            scored = _score_template(tmpl)
            # Optional LLM-based judging for richer story-level qualities.
            if judge_model:
                try:
                    judge_scores = _call_judge(
                        api_key=api_key,
                        model=judge_model,
                        template=tmpl,
                        temperature=judge_temperature,
                    )
                    scored.judge_scores = judge_scores
                    # Combine heuristic score with judge overall in a simple way.
                    overall = judge_scores.get("overall", 0.0)
                    scored.score += overall * 5.0  # weight judge fairly strongly
                    print(f"  Judge overall score: {overall:.2f}")
                except Exception as e:
                    print(f"  Judge failed: {e}")
            meta = {
                "generator_model": model,
                "generator_prompt_version": GENERATOR_PROMPT_VERSION,
                "judge_model": judge_model or "",
            }
            _save_template(
                tmpl, meta=meta
            )  # Persist regardless of score for later review.
            results.append(scored)
            print(
                f"Candidate {generated}: title='{tmpl.title}', "
                f"sentences={len(tmpl.sentences)}, slots={len(tmpl.slots)}, "
                f"score={scored.score:.2f}"
            )
    # Within-population motif diversity adjustment:
    # compute how often each coarse motif appears and apply
    # a small penalty to very common motifs so that, all else
    # equal, more distinctive stories rise.
    motif_counts: Dict[str, int] = {}
    for s in results:
        key = _motif_key(s.template)
        motif_counts[key] = motif_counts.get(key, 0) + 1
    for s in results:
        key = _motif_key(s.template)
        freq = motif_counts.get(key, 1)
        if freq > 1:
            # Light penalty: each extra story sharing this motif
            # key subtracts a small amount.
            penalty = 0.5 * (freq - 1)
            s.score -= penalty
    # Sort best to worst.
    results.sort(key=lambda s: s.score, reverse=True)
    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate and score multiple Mad Libs story templates."
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
        help="OpenRouter model id to use for generation (default: inception/mercury).",
    )
    parser.add_argument(
        "--judge-model",
        type=str,
        default="",
        help="Optional OpenRouter model id to use for judging (default: none).",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=5,
        help="Number of candidate templates to generate (default: 5).",
    )
    args = parser.parse_args()
    judge_model = args.judge_model or None

    scored = evolve(
        level=args.level,
        model=args.model,
        count=args.count,
        judge_model=judge_model,
    )

    print("\n=== Ranked candidates (best to worst) ===")
    for idx, s in enumerate(scored, 1):
        t = s.template
        line = (
            f"{idx}. score={s.score:.2f}, "
            f"title='{t.title}', "
            f"sentences={len(t.sentences)}, slots={len(t.slots)}, "
            f"abstract_penalty={s.details['abstract_penalty']}, "
            f"density_penalty={s.details['density_penalty']}"
        )
        if s.judge_scores:
            line += (
                f", judge_overall={s.judge_scores.get('overall', 0.0):.2f}, "
                f"judge_story_arc={s.judge_scores.get('story_arc', 0.0):.2f}, "
                f"judge_engagement={s.judge_scores.get('character_engagement', 0.0):.2f}"
            )
        print(line)


if __name__ == "__main__":
    main()


