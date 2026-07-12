#!/usr/bin/env python3
"""Fail-closed semantic checks for historical log transcription ledgers."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path


SCHEMA = "yard.arena.log-transcription.v0"
ALLOWED_STATUS = {"catalogue_verified", "single_transcription", "double_transcription", "adjudicated"}


def validate(path: Path) -> dict[str, object]:
    raw = path.read_bytes()
    document = json.loads(raw)
    if document.get("schema_version") != SCHEMA:
        raise ValueError("unsupported schema_version")
    source = document.get("source")
    if not isinstance(source, dict) or source.get("license") != "Open Government Licence":
        raise ValueError("Mercury ledger must retain its Open Government Licence marker")
    records = document.get("records")
    if not isinstance(records, list) or not records:
        raise ValueError("records must be a non-empty list")
    identifiers: set[str] = set()
    previous_date: dt.date | None = None
    transcription_records = 0
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            raise ValueError(f"record {index} is not an object")
        record_id = record.get("record_id")
        if not isinstance(record_id, str) or not record_id or record_id in identifiers:
            raise ValueError(f"record {index} has an empty or duplicate record_id")
        identifiers.add(record_id)
        date = dt.date.fromisoformat(record["date_iso"])
        if previous_date is not None and date < previous_date:
            raise ValueError(f"record {record_id} is not chronological")
        previous_date = date
        confidence = record.get("confidence", {})
        if set(confidence) != {"date", "folio", "place", "transcription"}:
            raise ValueError(f"record {record_id} has incomplete confidence fields")
        if any(not isinstance(value, (int, float)) or not 0 <= value <= 1 for value in confidence.values()):
            raise ValueError(f"record {record_id} has confidence outside [0,1]")
        review = record.get("review", {})
        if review.get("status") not in ALLOWED_STATUS:
            raise ValueError(f"record {record_id} has invalid review status")
        raw_text = record.get("raw_text")
        if record.get("record_type") != "catalogue_route_anchor":
            transcription_records += 1
            if not isinstance(raw_text, str) or not raw_text.strip():
                raise ValueError(f"record {record_id} requires raw_text")
            if review.get("status") == "catalogue_verified":
                raise ValueError(f"record {record_id} cannot use catalogue-only review status")
        elif raw_text is not None or confidence["transcription"] != 0:
            raise ValueError(f"catalogue anchor {record_id} must not impersonate a page transcription")
    return {
        "valid": True,
        "schema_version": SCHEMA,
        "records": len(records),
        "transcription_records": transcription_records,
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ledger", type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.ledger), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
