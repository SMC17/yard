"""Ship-D schema + projection tests."""

from __future__ import annotations

from yard_sea_v0.hull import evaluate_l0
from yard_sea_v0.shipd import (
    LABELS,
    constraint_checklist,
    load_sample_vectors,
    load_schema,
    project_to_hull,
)


def test_labels_len_45():
    assert len(LABELS) == 45
    assert LABELS[0] == "LOA"
    assert LABELS[-1] == "Rsb"


def test_schema_groups():
    s = load_schema()
    assert len(s["groups"]["principal"]) == 7
    assert len(s["groups"]["midship"]) == 4
    assert len(s["groups"]["bow"]) == 9
    assert len(s["groups"]["stern"]) == 11
    assert len(s["groups"]["bulbs"]) == 14


def test_sample_vectors_project_and_l0():
    samples = load_sample_vectors()
    assert len(samples) >= 3
    ok = 0
    for v in samples[:5]:
        h = project_to_hull(v)
        assert h.L > 0 and h.B > 0 and h.T > 0
        if evaluate_l0(h).feasible:
            ok += 1
    assert ok >= 1


def test_constraints_documented():
    c = constraint_checklist()
    assert c["n"] == 49
    assert c["status"] == "not_evaluated_in_yard_sea_v0"
