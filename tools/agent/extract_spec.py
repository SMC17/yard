#!/usr/bin/env python3
"""
Extract box-barge stability problem specs from natural language.

Modes:
  regex   — fast deterministic patterns
  ollama  — LLM structured extraction (spec only, no numerics)
  hybrid  — ollama with regex fallback
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Literal

sys.path.insert(0, str(Path(__file__).parent.parent / "finetune"))
from json_extract import extract_json  # noqa: E402

ExtractMode = Literal["regex", "ollama", "hybrid"]

EXTRACT_SYSTEM = """You extract box-barge stability problem parameters from natural language.
Respond with ONLY a JSON object (no markdown fences, no commentary):
{
  "L": <float, length meters>,
  "B": <float, beam meters>,
  "T": <float, draft meters>,
  "kg_m": <float, KG above keel meters>,
  "tanks": [{"l_m": <float>, "b_m": <float>, "rho_fluid": <float kg/m3>}]
}
Rules:
- "tanks" is [] when there are no slack tanks.
- rho_fluid: 1000 for fresh water, 1025 for seawater/salt water; read density from text if given.
- Do NOT compute GM, GZ, IS Code, or pass/fail — extraction only.
"""


def _first_float(text: str, patterns: list[str]) -> float | None:
    for pat in patterns:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            return float(m.group(1))
    return None


def extract_spec_regex(text: str) -> tuple[dict[str, Any], list[str]]:
    notes: list[str] = []
    l_m = _first_float(text, [
        r"LPP\s*=\s*([\d.]+)",
        r"(?:^|\s)L\s*=\s*([\d.]+)\s*m",
        r"(?:^|[\s□])L\s*=\s*([\d.]+)\s*m",
        r"(\d+(?:\.\d+)?)\s*m\s+long",
        r"L\s*=\s*([\d.]+)",
    ])
    b_m = _first_float(text, [
        r"(\d+(?:\.\d+)?)\s*m\s+beam",
        r"(?:^|[\s□])B\s*=\s*([\d.]+)\s*m",
        r"B\s*=\s*([\d.]+)",
    ])
    t_m = _first_float(text, [
        r"(\d+(?:\.\d+)?)\s*m\s+draft",
        r"draft\s+T\s*=\s*([\d.]+)",
        r"(?:^|[\s□])T\s*=\s*([\d.]+)\s*m",
        r"T\s*=\s*([\d.]+)\s*m",
        r"T\s*=\s*([\d.]+)",
    ])
    kg_m = _first_float(text, [
        r"(?:^|[\s□])KG\s*=\s*([\d.]+)\s*m",
        r"KG\s*=\s*([\d.]+)\s*m",
        r"KG\s*=\s*([\d.]+)",
        r"[Cc]enter of gravity is\s+([\d.]+)\s*m",
        r"gravity\s+is\s+([\d.]+)\s*m",
    ])

    if None in (l_m, b_m, t_m, kg_m):
        raise ValueError(
            f"regex could not extract L/B/T/KG: L={l_m} B={b_m} T={t_m} KG={kg_m}"
        )

    tanks: list[dict[str, float]] = []
    for m in re.finditer(
        r"Tank\s*\d*\s*:\s*([\d.]+)\s*[×x]\s*([\d.]+)\s*m(?:\s*\(([^)]+)\))?",
        text,
        re.IGNORECASE,
    ):
        rho = 1000.0
        fluid = (m.group(3) or "").lower()
        if "sea" in fluid:
            rho = 1025.0
        elif re.search(r"ρ\s*=\s*(\d+)", fluid):
            rho = float(re.search(r"ρ\s*=\s*(\d+)", fluid).group(1))
        tanks.append({"l_m": float(m.group(1)), "b_m": float(m.group(2)), "rho_fluid": rho})

    if not tanks and re.search(r"no\s+slack\s+tank", text, re.IGNORECASE):
        notes.append("explicit_no_tanks")

    return {
        "L": l_m,
        "B": b_m,
        "T": t_m,
        "kg_m": kg_m,
        "tanks": tanks,
    }, notes


def _ollama_chat(
    model: str,
    user: str,
    *,
    host: str = "http://127.0.0.1:11434",
    timeout: float = 120.0,
) -> tuple[str, float]:
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": EXTRACT_SYSTEM},
            {"role": "user", "content": user},
        ],
        "stream": False,
        "options": {"temperature": 0.0, "num_predict": 256},
    }).encode()
    req = urllib.request.Request(
        f"{host}/api/chat",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read())
    msg = data.get("message", {})
    return msg.get("content", ""), time.time() - t0


def _normalize_spec(raw: dict[str, Any]) -> dict[str, Any]:
    required = ("L", "B", "T", "kg_m")
    for key in required:
        if key not in raw:
            raise ValueError(f"missing key: {key}")
    tanks_raw = raw.get("tanks", [])
    if tanks_raw is None:
        tanks_raw = []
    if not isinstance(tanks_raw, list):
        raise ValueError("tanks must be a list")

    tanks: list[dict[str, float]] = []
    for t in tanks_raw:
        if not isinstance(t, dict):
            continue
        tanks.append({
            "l_m": float(t.get("l_m", t.get("length_m", 0))),
            "b_m": float(t.get("b_m", t.get("breadth_m", 0))),
            "rho_fluid": float(t.get("rho_fluid", t.get("rho", 1000.0))),
        })

    return {
        "L": float(raw["L"]),
        "B": float(raw["B"]),
        "T": float(raw["T"]),
        "kg_m": float(raw["kg_m"]),
        "tanks": tanks,
    }


def extract_spec_ollama(
    text: str,
    *,
    model: str = "qwen2.5-coder:1.5b",
    host: str = "http://127.0.0.1:11434",
) -> tuple[dict[str, Any], list[str]]:
    notes: list[str] = []
    raw_text, latency = _ollama_chat(model, text, host=host)
    notes.append(f"ollama_latency_s={latency:.2f}")
    notes.append(f"ollama_model={model}")

    parsed = extract_json(raw_text)
    if parsed is None:
        raise ValueError(f"ollama returned non-JSON: {raw_text[:200]!r}")

    try:
        spec = _normalize_spec(parsed)
    except (TypeError, ValueError) as e:
        raise ValueError(f"ollama spec invalid: {e}") from e

    return spec, notes


def extract_spec(
    text: str,
    mode: ExtractMode = "hybrid",
    *,
    model: str = "qwen2.5-coder:1.5b",
    host: str = "http://127.0.0.1:11434",
) -> tuple[dict[str, Any], list[str], str]:
    """Returns (spec, notes, extraction_mode_used)."""
    if mode == "regex":
        spec, notes = extract_spec_regex(text)
        return spec, notes, "instruction_regex"

    if mode == "ollama":
        spec, notes = extract_spec_ollama(text, model=model, host=host)
        return spec, notes, "ollama_extract"

    try:
        spec, notes = extract_spec_ollama(text, model=model, host=host)
        return spec, notes, "ollama_extract"
    except (urllib.error.URLError, ValueError, TimeoutError) as e:
        notes = [f"ollama_failed={e!s}"]
        try:
            spec, regex_notes = extract_spec_regex(text)
            notes.extend(regex_notes)
            notes.append("fallback=regex")
            return spec, notes, "hybrid_regex_fallback"
        except ValueError:
            raise ValueError(f"hybrid extraction failed: ollama={e}") from e