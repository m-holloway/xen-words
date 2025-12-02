"""
Generate starting fragment prompts for interactive Story Time sessions.

This script calls OpenRouter once to produce ~80 short opening fragments,
some of which include blanks (like "Once upon a time, there was a really
really _____") that invite the child to help complete the idea.

Output:
    genai/story_fragments.json

Usage:
    cd genai
    python generate_story_fragments.py
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Any

import urllib.request
import urllib.error


def load_env() -> Dict[str, str]:
    """Minimal .env loader from the genai directory."""
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
    return env_vars


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
    start = stripped.find("{")
    end = stripped.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise json.JSONDecodeError("No JSON object found", stripped, 0)
    return stripped[start : end + 1]


def build_fragment_prompt() -> Dict[str, Any]:
    system = (
        "You are a children's story prompt designer. Your job is to create short, "
        "vivid opening fragments for bedtime stories that a parent and child will "
        "complete together.\n\n"
        "Some fragments should be full clauses that end in a comma or feel like a "
        "teaser, and some should include a single blank represented by '_____'.\n\n"
        "Constraints:\n"
        "- 8–15 words per fragment\n"
        "- Warm, imaginative, age-appropriate for 4–8 year olds\n"
        "- Use simple, concrete language (avoid abstract vocabulary)\n"
        "- Avoid anything scary, dark, or upsetting (no real-world harm)\n"
        "- Mix cozy, adventurous, and slightly mysterious tones\n"
        "- Blanks should invite fun adjectives, roles, or surprises, e.g.\n"
        "  * 'Once upon a time, there was a really really _____'\n"
        "  * 'On a rainy morning, a little fox found a _____'\n\n"
        "Output JSON only, no commentary."
    )

    user = {
        "instructions": (
            "Generate about 80 diverse opening fragments. Return JSON:\n"
            "{\n"
            '  "fragments": [\n'
            '    "Once upon a time, there was a really really _____.",\n'
            '    "On the edge of the forest, a tiny door was glowing,",\n'
            '    "Under her bed, Mia kept a secret box full of _____.",\n'
            '    "... more like this ..."\n'
            "  ]\n"
            "}\n"
        )
    }

    return {
        "system": system,
        "user": user,
    }


def main() -> None:
    env = load_env()
    api_key = env.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("OPENROUTER_API_KEY not found in genai/.env")

    model = env.get(
        "STORY_BUILDER_BY_SENTENCE_MODEL",
        env.get("INTERACTIVE_STORY_MODEL", env.get("DEFAULT_MODEL", "gpt-4o-mini")),
    )

    cfg = build_fragment_prompt()

    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": cfg["system"]},
            {
                "role": "user",
                "content": json.dumps(cfg["user"], ensure_ascii=False),
            },
        ],
        "temperature": 0.9,
        "max_output_tokens": 2048,
    }

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://xen.words.app/dev",
        "X-Title": "Xen Words - Story Fragment Generator",
    }

    print(f"Calling OpenRouter model={model} to generate starting fragments...")
    data_bytes = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", method="POST"
    )
    for k, v in headers.items():
        req.add_header(k, v)
    req.data = data_bytes

    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            raw = response.read().decode("utf-8")
            data = json.loads(raw)
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        raise SystemExit(f"OpenRouter API error {e.code}: {error_body}")
    except Exception as e:
        raise SystemExit(f"Request failed: {e}")

    content = data["choices"][0]["message"]["content"]
    text = _strip_markdown_fences(content)
    try:
        extracted = _extract_first_json_object(text)
        parsed = json.loads(extracted)
    except json.JSONDecodeError:
        print("Model did not return valid JSON; raw output (first 800 chars):")
        print(text[:800])
        raise SystemExit("Adjust prompts or inspect raw output.")

    fragments = parsed.get("fragments") or []
    if not isinstance(fragments, list) or not fragments:
        raise SystemExit("No 'fragments' list found in model output.")

    # Normalize to strings and strip whitespace
    fragments = [str(f).strip() for f in fragments if str(f).strip()]

    out_path = Path(__file__).parent / "story_fragments.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump({"fragments": fragments}, f, ensure_ascii=False, indent=2)

    print(f"Saved {len(fragments)} fragments to {out_path}")


if __name__ == "__main__":
    main()


