#!/usr/bin/env python3
"""
Run fine-tuned LoRA adapter on eval set via transformers (no Ollama).

Usage:
  source tools/finetune/gpu_env.sh
  python tools/finetune/infer_local.py \
    --adapter models/yard-stability-smoke-v1/checkpoint-25 \
    --dataset tools/dataset/out/eval.jsonl \
    --output tools/gap_audit/out/smoke_preds.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "gap_audit"))
sys.path.insert(0, str(Path(__file__).parent))
from gap_audit import SYSTEM_PROMPT  # noqa: E402
from json_extract import extract_json  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adapter", type=Path, required=True)
    parser.add_argument("--base", default="Qwen/Qwen2.5-0.5B-Instruct")
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--max-new-tokens", type=int, default=256,
                        help="JSON-only answers need ~150-200 tokens")
    parser.add_argument("--score", action="store_true", help="Run gap_audit score after infer")
    args = parser.parse_args()

    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

    if not torch.cuda.is_available():
        print("ERROR: CUDA required", file=sys.stderr)
        sys.exit(1)

    bnb = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=False,
    )
    tokenizer = AutoTokenizer.from_pretrained(args.base, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    base = AutoModelForCausalLM.from_pretrained(
        args.base,
        quantization_config=bnb,
        device_map="auto",
        trust_remote_code=True,
        torch_dtype=torch.float16,
    )
    model = PeftModel.from_pretrained(base, str(args.adapter))
    model.eval()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with args.dataset.open() as fin, args.output.open("w") as fout:
        for line in fin:
            if args.limit and count >= args.limit:
                break
            rec = json.loads(line)
            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": rec["instruction"]},
            ]
            prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
            with torch.no_grad():
                out = model.generate(
                    **inputs,
                    max_new_tokens=args.max_new_tokens,
                    do_sample=False,
                    pad_token_id=tokenizer.pad_token_id,
                )
            raw = tokenizer.decode(out[0][inputs["input_ids"].shape[1] :], skip_special_tokens=True)
            pred = extract_json(raw) or {}
            fout.write(json.dumps({"id": rec["id"], "prediction": pred, "raw": raw[:2000]}) + "\n")
            count += 1
            print(f"  [{count}] {rec['id'][:8]}…", flush=True)

    print(f"Wrote {count} predictions to {args.output}")

    if args.score:
        import subprocess
        subprocess.run([
            sys.executable,
            str(Path(__file__).parent.parent / "gap_audit" / "score_preds.py"),
            "--dataset", str(args.dataset),
            "--predictions", str(args.output),
            "--model-name", str(args.adapter),
        ], check=False)


if __name__ == "__main__":
    main()