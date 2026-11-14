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
    run.add_argument(
        "--env45",
        action="store_true",
        help="Use DesignSearchEnv45 (Box(45) Ship-D actions) instead of 7-D DesignSearchEnv",
    )
    run.add_argument(
        "--l15-michell",
        action="store_true",
        help="Attach Michell L1.5 wave-drag teacher per child hull (vendored ModMichell)",
    )
    run.add_argument(
        "--l2-panel",
        action="store_true",
        help="Attach Capytaine L2 panel/BEM teacher per child (skips if capytaine missing)",
    )
    run.add_argument(
        "--botorch",
        action="store_true",
        help="Enable BoTorch Bayesian optimization search path (requires botorch/torch)",
    )
    run.add_argument(
        "--multifidelity",
        action="store_true",
        help="Stage A L1(/L1.5) search then Stage B L3_rans on top-k elites only",
    )
    run.add_argument(
        "--l3-top",
        type=int,
        default=3,
        metavar="K",
        help="With --multifidelity: number of Stage-A elites to evaluate at L3 (default 3)",
    )
    run.add_argument(
        "--reward",
        choices=("single_fn", "multi_froude"),
        default="single_fn",
        help="Reward: design-Fn Ct only, or multi-Froude grid with worst-case penalty",
    )
    run.add_argument(
        "--wave-oracle",
        choices=("auto", "l1", "michell"),
        default="auto",
        help=(
            "Wave term for --reward multi_froude. auto = L1 when it is Zig HM1984, "
            "else Michell L1.5 (the Python L1 wave term is damped); resolved choice is recorded"
        ),
    )
    run.add_argument(
        "--holdout",
        action="store_true",
        help="Post-hoc held-out oracle check + drift diagnostics (never enters reward)",
    )
    run.add_argument(
        "--holdout-oracle",
        choices=("michell", "hm1984", "capytaine_l2"),
        default="michell",
        help=(
            "Held-out oracle for --holdout: Michell L1.5 wave (default), Zig HM1984 L1, or "
            "Capytaine L2 box BEM (blind to Cb/lcb/kg). independent_of_reward is recorded"
        ),
    )
    run.add_argument(
        "--no-cost-aware",
        action="store_true",
        help="With --multifidelity --botorch: use plain BoTorch EI instead of cost-weighted qLogEI",
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

    act45 = sub.add_parser(
        "act45",
        help="Smoke DesignSearchEnv45: zero + random 45-D steps on a sample vector",
    )
    act45.add_argument("--sample", type=int, default=0)
    act45.add_argument("--steps", type=int, default=8)
    act45.add_argument("--seed", type=int, default=0)
    act45.add_argument("--delta-frac", type=float, default=0.05)

    args = p.parse_args(argv)

    if args.cmd == "run-search":
        if getattr(args, "env45", False):
            from .search import run_env45_search

            rows = run_env45_search(
                n_samples=args.parents,
                steps=args.steps,
                seed=args.seed,
                out_dir=args.out,
            )
            n_ok = sum(1 for r in rows if not r.get("all_rejected"))
            print(
                f"env45 search out={args.out} episodes={len(rows)} "
                f"with_accepts={n_ok}"
            )
            return 0

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
            l15_michell=args.l15_michell,
            l2_panel=args.l2_panel,
            use_botorch=args.botorch,
            multifidelity=args.multifidelity,
            l3_top=args.l3_top,
            cost_aware=not args.no_cost_aware,
            reward_mode=args.reward,
            wave_oracle=args.wave_oracle,
            holdout=args.holdout,
            holdout_oracle=args.holdout_oracle,
        )
        print(
            f"Wrote {args.out} improved={manifest['n_improved']} "
            f"best_dCt={manifest['best_delta_ct']:.6f} "
            f"shipd={manifest.get('use_shipd')} corpus={manifest.get('use_corpus')} "
            f"botorch={manifest.get('use_botorch')} l3={manifest.get('l3_openfoam')} "
            f"mf={manifest.get('multifidelity')} l3_top={manifest.get('l3_top')}"
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

    if args.cmd == "act45":
        import numpy as np

        from .env45 import ACTION_DIM, DesignSearchEnv45

        env = DesignSearchEnv45(
            sample_index=args.sample,
            max_steps=args.steps,
            seed=args.seed,
            delta_frac=args.delta_frac,
        )
        obs, info = env.reset()
        rng = np.random.default_rng(args.seed)
        n_rej = 0
        n_shipd = 0
        _, r0, _, _, i0 = env.step(np.zeros(ACTION_DIM))
        print(
            f"act45 sample={args.sample} zero rejected={i0['rejected']} "
            f"shipd_infeas={i0.get('shipd_infeasible')} reward={r0:.4f}"
        )
        for _ in range(max(0, args.steps - 1)):
            a = rng.uniform(-1, 1, size=ACTION_DIM).astype(np.float32)
            _, r, _, _, inf = env.step(a)
            if inf.get("rejected"):
                n_rej += 1
            if inf.get("shipd_infeasible"):
                n_shipd += 1
        print(
            f"act45 random_steps={max(0, args.steps - 1)} rejected={n_rej} "
            f"shipd_infeasible={n_shipd} action_dim={ACTION_DIM} "
            f"seed_feasible={info['shipd_feasible']}"
        )
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
