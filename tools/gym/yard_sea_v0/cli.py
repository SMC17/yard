"""CLI entrypoints."""

from __future__ import annotations

import argparse
from pathlib import Path

from .gallery import write_gallery


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="yard_sea_v0")
    sub = p.add_subparsers(dest="cmd", required=True)
    run = sub.add_parser("run-search", help="Run search gallery")
    run.add_argument("--parents", type=int, default=5)
    run.add_argument("--steps", type=int, default=40)
    run.add_argument("--seed", type=int, default=0)
    run.add_argument("--out", type=Path, default=Path("out/gallery"))
    run.add_argument(
        "--shipd",
        action="store_true",
        help="Seed parents from public Ship-D sample vectors",
    )
    args = p.parse_args(argv)
    if args.cmd == "run-search":
        manifest = write_gallery(
            args.out,
            n_parents=args.parents,
            steps=args.steps,
            seed=args.seed,
            use_shipd=args.shipd,
        )
        print(
            f"Wrote {args.out} improved={manifest['n_improved']} "
            f"best_dCt={manifest['best_delta_ct']:.6f} shipd={manifest.get('use_shipd')}"
        )
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
