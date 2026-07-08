"""Robust JSON extraction for stability model outputs."""

from __future__ import annotations

import json
import re


def extract_json(text: str) -> dict | None:
    text = text.strip()
    # Prefer fenced JSON block (training format)
    fence = re.search(r"```(?:json)?\s*(\{[\s\S]*?\})\s*```", text, re.IGNORECASE)
    if fence:
        try:
            return _normalize(json.loads(fence.group(1)))
        except json.JSONDecodeError:
            pass

    # Brace-balanced scan (first complete object)
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    in_str = False
    esc = False
    for i, ch in enumerate(text[start:], start):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                try:
                    return _normalize(json.loads(text[start : i + 1]))
                except json.JSONDecodeError:
                    return None
    return None


def _normalize(obj: dict) -> dict:
    """Map common hallucinated keys to oracle schema."""
    if not isinstance(obj, dict):
        return obj
    out = dict(obj)
    crit = out.get("imo_criteria")
    if isinstance(crit, dict):
        crit = dict(crit)
        for bad, good in (
            ("gg_at_30", "gz_at_30"),
            ("gatekeeper_zone", "angle_gz_max"),
            ("angle_max", "angle_gz_max"),
        ):
            if bad in crit and good not in crit:
                crit[good] = crit.pop(bad)
        out["imo_criteria"] = crit
    if "banana_flags" in out and "flags" not in out:
        out["flags"] = out.pop("banana_flags")
    return out