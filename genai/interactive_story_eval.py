"""
Non-interactive evaluation harness for the interactive next-sentence model.

This script reuses the same system prompt and payload builder as
`interactive_next_sentence_demo.py`, but runs through a fixed set of test
patterns for different reading levels and prints simple metrics about how well
the returned sentences match the expected constraints.

Usage (from repo root):
    cd genai
    python interactive_story_eval.py
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Tuple

import urllib.error
import urllib.request

from interactive_next_sentence_demo import (
    _build_payload,
    _parse_model_output,
    _system_prompt,
    load_env,
)


@dataclass
class EvalTestCase:
    name: str
    reading_level: int
    seed: str


def _reading_band_for_level(level: int) -> Dict[str, Any]:
    # Mirror the bands used in the demo CLI, but as a reusable helper.
    bands: Dict[int, Dict[str, Any]] = {
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
    level = max(1, min(5, level))
    return bands[level]


def _reading_metrics(sentence: str) -> Dict[str, Any]:
    words = [w.strip(".,!?;:\"'()").lower() for w in sentence.split() if w.strip()]
    word_count = len(words)
    avg_len = sum(len(w) for w in words) / word_count if word_count else 0.0
    long_words = [w for w in words if len(w) >= 7]
    caps_inside = sum(1 for ch in sentence[1:] if ch.isupper())
    commas = sentence.count(",")
    exclaims = sentence.count("!")
    periods = sentence.count(".")
    return {
        "word_count": word_count,
        "avg_word_len": avg_len,
        "long_word_count": len(long_words),
        "internal_capitals": caps_inside,
        "comma_count": commas,
        "exclaim_count": exclaims,
        "period_count": periods,
    }


def _expected_constraints(level: int) -> Dict[str, Any]:
    # Very rough heuristic constraints per reading level. These are not
    # ground truth; they just help highlight when the model obviously ignores
    # the level band (e.g. 20-word sentences at level 1).
    if level == 1:
        return {
            "max_words": 8,
            "max_long_words": 0,
            "max_commas": 0,
        }
    if level == 2:
        return {
            "max_words": 14,
            "max_long_words": 1,
            "max_commas": 1,
        }
    if level == 3:
        return {
            "max_words": 20,
            "max_long_words": 3,
            "max_commas": 2,
        }
    if level == 4:
        return {
            "max_words": 28,
            "max_long_words": 5,
            "max_commas": 3,
        }
    return {
        "max_words": 40,
        "max_long_words": 8,
        "max_commas": 4,
    }


def _check_constraints(metrics: Dict[str, Any], constraints: Dict[str, Any]) -> Dict[str, bool]:
    return {
        "ok_word_count": metrics["word_count"] <= constraints["max_words"],
        "ok_long_words": metrics["long_word_count"] <= constraints["max_long_words"],
        "ok_commas": metrics["comma_count"] <= constraints["max_commas"],
    }


def _choose_model(env: Dict[str, str]) -> Tuple[str, str]:
    if env.get("STORY_BUILDER_BY_SENTENCE_MODEL"):
        return env["STORY_BUILDER_BY_SENTENCE_MODEL"], "STORY_BUILDER_BY_SENTENCE_MODEL"
    if env.get("INTERACTIVE_STORY_MODEL"):
        return env["INTERACTIVE_STORY_MODEL"], "INTERACTIVE_STORY_MODEL"
    # Match the fallback in the interactive demo.
    return "qwen/qwen3-next-80b-a3b-instruct", "hardcoded fallback (qwen/qwen3-next-80b-a3b-instruct)"


def _call_model(
    *,
    api_key: str,
    model: str,
    payload: Dict[str, Any],
) -> Dict[str, Any]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Story Eval Harness",
    }
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
        "temperature": 0.7,
        "max_output_tokens": 512,
        "usage": {"include": True},
        "user": "story_builder_eval_harness",
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


def run_eval() -> None:
    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env")

    model, model_source = _choose_model(env)
    print(f"Eval using model={model} (source={model_source})")

    tests: List[EvalTestCase] = [
        EvalTestCase(
            name="L1-decoder-simple",
            reading_level=1,
            seed="Sam can run.",
        ),
        EvalTestCase(
            name="L1-fragment",
            reading_level=1,
            seed="See Sam",
        ),
        EvalTestCase(
            name="L2-simple-story",
            reading_level=2,
            seed="The little cat sat on the rug.",
        ),
        EvalTestCase(
            name="L3-richer",
            reading_level=3,
            seed="On a warm day, Mia walked to the park.",
        ),
        EvalTestCase(
            name="L4-dialogue",
            reading_level=4,
            seed='"Let\'s try again," Leo said, picking up the kite string.',
        ),
        EvalTestCase(
            name="L5-figurative",
            reading_level=5,
            seed="The city lights flickered like a net of tiny stars below the hill.",
        ),
    ]

    project_root = Path(__file__).resolve().parent.parent
    log_path = project_root / "docs" / "INTERACTIVE_STORY_MODE_EVAL_LOG.md"

    with log_path.open("a", encoding="utf-8") as log_file:
        log_file.write(
            f"\n\n### Eval run at {datetime.now().isoformat()} "
            f"(model={model}, source={model_source})\n"
        )

        for tc in tests:
            print(f"\n--- Test: {tc.name} (level={tc.reading_level}) ---")
            band = _reading_band_for_level(tc.reading_level)
            payload = _build_payload(
                num_candidates=3,
                story_so_far=[tc.seed],
                child_line=tc.seed,
                guidance=None,
                reading_level=tc.reading_level,
                reading_band=band,
            )
            payload["tuning_tokens"] = {"crazy": 0, "challenge": 0, "cozy": 0}

            try:
                data = _call_model(api_key=api_key, model=model, payload=payload)
            except urllib.error.HTTPError as e:
                body = e.read().decode("utf-8", errors="replace")
                print(f"HTTPError {e.code}: {body[:400]}")
                log_file.write(f"- {tc.name}: HTTPError {e.code}\n")
                continue
            except Exception as e:
                print(f"Request failed: {e}")
                log_file.write(f"- {tc.name}: request failed: {e}\n")
                continue

            usage = data.get("usage")
            if usage:
                print(f"  usage: {usage}")

            content = data["choices"][0]["message"]["content"]
            parsed = _parse_model_output(str(content or ""))
            candidates = (parsed.get("candidates") or [])[:3]
            constraints = _expected_constraints(tc.reading_level)

            log_file.write(f"- **{tc.name}** (level {tc.reading_level})\n")
            log_file.write(f"  - seed: `{tc.seed}`\n")
            for idx, cand in enumerate(candidates, 1):
                sent = (cand.get("sentence") or "").strip()
                m = _reading_metrics(sent)
                flags = _check_constraints(m, constraints)
                print(f"  cand {idx}: {sent}")
                print(f"    metrics={m}, flags={flags}")
                log_file.write(f"  - cand {idx}: {sent}\n")
                log_file.write(f"    - metrics: {m}\n")
                log_file.write(f"    - flags: {flags}\n")


if __name__ == "__main__":
    run_eval()


