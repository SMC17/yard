"""CLI entrypoints."""

from __future__ import annotations

import argparse
from pathlib import Path


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
        help="Seed parents from public Ship-D sample vectors (CSV)",
    )
    run.add_argument(
        "--corpus",
        type=int,
        default=None,
        metavar="N",
        help="Seed N parents from InputVectors_30k.npy corpus",
    )
    run.add_argument(
        "--l3-openfoam",
        action="store_true",
        help="Attach OpenFOAM L3 teacher scaffold per child (skips if FOAM unavailable)",
    )

    ingest = sub.add_parser(
        "ingest-shipd",
        help="Ensure 30k vectors present; probe Dataverse; write ingest manifest",
    )
    ingest.add_argument(
        "--out",
        type=Path,
        default=Path("out/dataverse_ingest_manifest.json"),
        help="Path for JSON ingest manifest",
    )

    args = p.parse_args(argv)

    if args.cmd == "run-search":
        from .gallery import write_gallery

        n_parents = args.parents
        use_corpus = args.corpus is not None
        if use_corpus:
            n_parents = int(args.corpus)
        manifest = write_gallery(
            args.out,
            n_parents=n_parents,
            steps=args.steps,
            seed=args.seed,
            use_shipd=args.shipd and not use_corpus,
            use_corpus=use_corpus,
            l3_openfoam=args.l3_openfoam,
        )
        print(
            f"Wrote {args.out} improved={manifest['n_improved']} "
            f"best_dCt={manifest['best_delta_ct']:.6f} "
            f"shipd={manifest.get('use_shipd')} corpus={manifest.get('use_corpus')}"
        )
        return 0

    if args.cmd == "ingest-shipd":
        from .corpus import ingest_shipd

        result = ingest_shipd(out_manifest=args.out)
        c = result["corpus"]
        print(
            f"ingest-shipd ok vectors={c['n_vectors']}x{c['n_dims']} "
            f"bytes={c['bytes']} path={c['path']}"
        )
        if result.get("dataverse_probe"):
            dv = result["dataverse_probe"]
            print(
                f"dataverse n_files={dv['n_files']} total_bytes={dv['total_bytes']} "
                f"license={(dv.get('license') or {}).get('name')}"
            )
        elif result.get("dataverse_probe_error"):
            print(f"dataverse probe error: {result['dataverse_probe_error']}")
        print(f"manifest={args.out}")
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
