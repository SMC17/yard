"""Sync guard for the shared split-conformal module (canonical here, vendored in SMC17/strip).

If this fails after an intentional edit: copy the file byte-for-byte to
SMC17/strip tools/gym/strip_uas_v0/conformal.py and update CONFORMAL_SHA256 in
both repos' tests/test_conformal_sync.py in the same change.
"""

import hashlib
import os
from pathlib import Path

import pytest

CONFORMAL_SHA256 = "61412a7b6393fe749f0f9d01520f3d540de99460c197bf7cb7c9479f0c72ce11"
HERE = Path(__file__).resolve().parents[1] / "yard_sea_v0" / "conformal.py"
SIBLING_REL = Path("tools/gym/strip_uas_v0/conformal.py")


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def test_conformal_matches_pinned_checksum():
    assert _sha(HERE) == CONFORMAL_SHA256


def _sibling() -> Path | None:
    env = os.environ.get("CONFORMAL_SIBLING_REPO")
    cands = [Path(env)] if env else []
    root = Path(__file__).resolve().parents[3]
    cands += [root.parent / n for n in ("strip", "wide-strip", "SMC17-strip")]
    for c in cands:
        if (c / SIBLING_REL).is_file():
            return c / SIBLING_REL
    return None


def test_conformal_identical_to_sibling_checkout_if_present():
    sib = _sibling()
    if sib is None:
        pytest.skip("no SMC17/strip checkout next to this repo (set CONFORMAL_SIBLING_REPO)")
    assert _sha(sib) == _sha(HERE), f"{sib} differs from the canonical yard copy"


def test_module_is_domain_neutral_and_pure_numpy():
    src = HERE.read_text()
    for word in ("hull", "wing", "Froude", "NeuralFoil", "Michell"):
        assert word not in src
    imports = [ln for ln in src.splitlines() if ln.startswith(("import ", "from "))]
    assert all(m.split()[1].split(".")[0] in {"__future__", "math", "dataclasses", "typing", "numpy"}
               for m in imports)
