#!/usr/bin/env python3
"""Build the Mercury route weather ensemble from the licensed CLIWOC core.

The output is a compact empirical joint histogram, not reconstructed weather.
It retains the source digest, selection window, route corridor, bin edges, and
observation counts needed to audit or regenerate every evaluator season.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import zipfile
from dataclasses import dataclass
from pathlib import Path


SCHEMA = "yard.arena.historical-environment.v0"
SOURCE_URL = "https://hs.pangaea.de/Projects/CLIWOC/CLIWOC21CORE.zip"
SOURCE_DOI = "https://doi.org/10.1594/PANGAEA.743343"
SOURCE_SHA256 = "b574909d59cc5d3f9bbf9b65eadf1358d5eae23d7f63dc8f8f0a740be8476be7"
SOURCE_MEMBER = "CLIWOC21CORE.txt"

SPEED_EDGES = [0.0, 1.0, 3.0, 5.0, 7.0, 9.0, 12.0, 15.0, 20.0, 30.0, 50.0]
ANGLE_EDGES = [float(v) for v in range(0, 181, 15)]


@dataclass(frozen=True)
class Point:
    name: str
    lat: float
    lon: float


ROUTE_LEGS = [
    (
        "downs-to-st-helena",
        [
            Point("The Downs", 51.15, 1.35),
            Point("Madeira approach", 32.7, -16.9),
            Point("Atlantic equator", 0.0, -24.0),
            Point("St Helena", -15.965, -5.708),
        ],
    ),
    (
        "st-helena-to-table-bay",
        [
            Point("St Helena", -15.965, -5.708),
            Point("South Atlantic", -28.0, 2.0),
            Point("Table Bay", -33.90, 18.42),
        ],
    ),
    (
        "table-bay-to-bombay",
        [
            Point("Table Bay", -33.90, 18.42),
            Point("Cape south", -36.0, 25.0),
            Point("Mascarene corridor", -20.0, 55.0),
            Point("Bombay/Mumbai", 18.94, 72.84),
        ],
    ),
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_int(field: str) -> int | None:
    field = field.strip()
    if not field:
        return None
    try:
        return int(field)
    except ValueError:
        return None


def parse_core(raw: str) -> dict[str, object] | None:
    if len(raw) < 53:
        return None
    year = parse_int(raw[0:4])
    month = parse_int(raw[4:6])
    day = parse_int(raw[6:8])
    lat_raw = parse_int(raw[12:17])
    lon_raw = parse_int(raw[17:23])
    direction = parse_int(raw[46:49])
    speed_raw = parse_int(raw[50:53])
    if None in (year, month, day, lat_raw, lon_raw, direction, speed_raw):
        return None
    if not (1 <= month <= 12 and 1 <= day <= 31 and -9000 <= lat_raw <= 9000):
        return None
    if not (1 <= direction <= 360 and 0 <= speed_raw <= 500):
        return None
    lon = lon_raw / 100.0
    if lon > 180.0:
        lon -= 360.0
    if not -180.0 <= lon <= 180.0:
        return None
    return {
        "year": year,
        "month": month,
        "day": day,
        "lat": lat_raw / 100.0,
        "lon": lon,
        "wind_direction_deg": float(direction),
        "wind_speed_mps": speed_raw / 10.0,
        "ship_log_id": raw[34:43].strip(),
        "country": raw[43:45].strip(),
    }


def segment_distance_nm(lat: float, lon: float, a: Point, b: Point) -> float:
    """Local equirectangular point-to-segment distance for corridor selection."""
    mean_lat = math.radians((a.lat + b.lat + lat) / 3.0)
    scale = max(0.2, math.cos(mean_lat))
    ax, ay = a.lon * scale, a.lat
    bx, by = b.lon * scale, b.lat
    px, py = lon * scale, lat
    dx, dy = bx - ax, by - ay
    denom = dx * dx + dy * dy
    t = 0.0 if denom == 0.0 else ((px - ax) * dx + (py - ay) * dy) / denom
    t = min(1.0, max(0.0, t))
    distance_deg = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
    return distance_deg * 60.0


def nearest_leg(lat: float, lon: float, corridor_nm: float) -> int | None:
    best_index = None
    best_distance = float("inf")
    for index, (_, points) in enumerate(ROUTE_LEGS):
        distance = min(
            segment_distance_nm(lat, lon, points[i], points[i + 1])
            for i in range(len(points) - 1)
        )
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return best_index if best_distance <= corridor_nm else None


def initial_bearing_deg(a: Point, b: Point) -> float:
    lat1, lat2 = math.radians(a.lat), math.radians(b.lat)
    dlon = math.radians(b.lon - a.lon)
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def relative_wind_angle(direction_from_deg: float, course_deg: float) -> float:
    delta = abs(direction_from_deg - course_deg) % 360.0
    return min(delta, 360.0 - delta)


def bin_index(value: float, edges: list[float]) -> int | None:
    if value < edges[0] or value > edges[-1]:
        return None
    for index in range(len(edges) - 1):
        if edges[index] <= value < edges[index + 1]:
            return index
    return len(edges) - 2


def build_environment(
    zip_path: Path,
    year_min: int,
    year_max: int,
    corridor_nm: float,
) -> dict[str, object]:
    source_hash = sha256_file(zip_path)
    if source_hash != SOURCE_SHA256:
        raise ValueError(f"source SHA-256 mismatch: expected {SOURCE_SHA256}, got {source_hash}")

    speed_bins = len(SPEED_EDGES) - 1
    angle_bins = len(ANGLE_EDGES) - 1
    counts = [
        [[0] * (speed_bins * angle_bins) for _ in range(12)]
        for _ in ROUTE_LEGS
    ]
    observations = [[0] * 12 for _ in ROUTE_LEGS]
    examined = selected = 0
    course_bearings = [initial_bearing_deg(points[0], points[-1]) for _, points in ROUTE_LEGS]

    with zipfile.ZipFile(zip_path) as archive:
        with archive.open(SOURCE_MEMBER) as raw_handle:
            for raw in raw_handle:
                examined += 1
                record = parse_core(raw.decode("ascii", errors="replace"))
                if record is None or not year_min <= record["year"] <= year_max:
                    continue
                leg_index = nearest_leg(record["lat"], record["lon"], corridor_nm)
                if leg_index is None:
                    continue
                twa = relative_wind_angle(record["wind_direction_deg"], course_bearings[leg_index])
                speed_index = bin_index(record["wind_speed_mps"], SPEED_EDGES)
                angle_index = bin_index(twa, ANGLE_EDGES)
                if speed_index is None or angle_index is None:
                    continue
                month_index = record["month"] - 1
                counts[leg_index][month_index][speed_index * angle_bins + angle_index] += 1
                observations[leg_index][month_index] += 1
                selected += 1

    legs = []
    for leg_index, (leg_id, points) in enumerate(ROUTE_LEGS):
        monthly = []
        for month in range(1, 13):
            monthly.append(
                {
                    "month": month,
                    "observation_count": observations[leg_index][month - 1],
                    "joint_counts": counts[leg_index][month - 1],
                }
            )
        legs.append(
            {
                "leg_id": leg_id,
                "course_bearing_deg": course_bearings[leg_index],
                "route_nodes": [
                    {"name": p.name, "lat_deg": p.lat, "lon_deg": p.lon} for p in points
                ],
                "monthly": monthly,
            }
        )

    if any(month["observation_count"] == 0 for leg in legs for month in leg["monthly"]):
        raise ValueError("selection produced an empty leg/month cell; widen the auditable corridor")

    return {
        "schema_version": SCHEMA,
        "dataset_id": "cliwoc-mercury-route-1750-1805-v0",
        "source": {
            "title": "CLIWOC Database 2.1 (final release, original IMMA format)",
            "citation": "Garcia-Herrera, Ricardo (2007), PANGAEA, doi:10.1594/PANGAEA.743343",
            "doi": SOURCE_DOI,
            "download_url": SOURCE_URL,
            "license": "CC-BY-3.0",
            "archive_sha256": source_hash,
            "archive_member": SOURCE_MEMBER,
            "records_in_archive": examined,
        },
        "selection": {
            "year_min": year_min,
            "year_max": year_max,
            "route_corridor_nm": corridor_nm,
            "selected_observations": selected,
            "method": "nearest equirectangular route segment within fixed corridor; one record assigned to one leg",
        },
        "uncertainty": {
            "model_id": "empirical-joint-bin-bootstrap-v0",
            "represented": ["interannual variability", "seasonality", "joint wind speed and relative direction", "within-bin discretization"],
            "not_represented": ["exact 1778 trajectory", "ship-log transcription error", "position-error posterior", "instrument bias posterior", "climate nonstationarity"],
            "sampling": "categorical cell draw followed by uniform draw inside the published cell edges",
        },
        "wind_speed_edges_mps": SPEED_EDGES,
        "relative_wind_angle_edges_deg": ANGLE_EDGES,
        "legs": legs,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core-zip", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--year-min", type=int, default=1750)
    parser.add_argument("--year-max", type=int, default=1805)
    parser.add_argument("--corridor-nm", type=float, default=900.0)
    args = parser.parse_args()
    environment = build_environment(args.core_zip, args.year_min, args.year_max, args.corridor_nm)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(environment, indent=2, sort_keys=True) + "\n")
    print(
        json.dumps(
            {
                "output": str(args.output),
                "selected_observations": environment["selection"]["selected_observations"],
                "source_sha256": environment["source"]["archive_sha256"],
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
