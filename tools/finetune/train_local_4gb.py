#!/usr/bin/env python3
"""
QLoRA fine-tune for GTX 1650 4GB VRAM.

Optimized for narrow stability behavior on small models:
  - Qwen2.5-0.5B-Instruct (default, safest on 4GB)
  - Qwen2.5-1.5B-Instruct (--model flag, tighter memory)

Uses transformers + peft + bitsandbytes (no Unsloth required).

Usage:
  source tools/finetune/gpu_env.sh
  pip install bitsandbytes accelerate
  python tools/finetune/train_local_4gb.py \
    --data tools/dataset/out/train_chat.jsonl \
    --output models/yard-stability-4gb-v1 \
    --max-samples 1000   # start small, scale up
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def check_gpu() -> tuple[bool, str]:
    try:
        import torch
        if not torch.cuda.is_available():
            return False, "torch.cuda.is_available() is False — run: source tools/finetune/gpu_env.sh"
        name = torch.cuda.get_device_name(0)
        vram = torch.cuda.get_device_properties(0).total_memory / (1024**3)
        return True, f"{name} ({vram:.1f} GB)"
    except Exception as e:
        return False, str(e)


def load_dataset(path: Path, max_samples: int | None):
    from datasets import Dataset

    records = []
    with path.open() as f:
        for line in f:
            records.append(json.loads(line))
            if max_samples and len(records) >= max_samples:
                break
    return Dataset.from_list(records)


def main() -> None:
    parser = argparse.ArgumentParser(description="4GB VRAM QLoRA fine-tune")
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("models/yard-stability-4gb-v1"))
    parser.add_argument("--model", default="Qwen/Qwen2.5-0.5B-Instruct",
                        help="0.5B default; try Qwen/Qwen2.5-1.5B-Instruct on 4GB at your risk")
    parser.add_argument("--epochs", type=int, default=2)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--max-seq-len", type=int, default=1024)
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--grad-accum", type=int, default=8)
    parser.add_argument("--max-samples", type=int, default=None,
                        help="Limit training samples for smoke test")
    parser.add_argument("--lora-r", type=int, default=8)
    args = parser.parse_args()

    ok, gpu_info = check_gpu()
    if not ok:
        print(f"ERROR: GPU not ready: {gpu_info}", file=sys.stderr)
        print("Fix: pip install --force-reinstall nvidia-cublas-cu12 nvidia-cuda-runtime-cu12", file=sys.stderr)
        print("Then: source tools/finetune/gpu_env.sh", file=sys.stderr)
        sys.exit(1)
    print(f"GPU: {gpu_info}")

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig, TrainingArguments
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    from trl import SFTTrainer

    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=True,
    )

    print(f"Loading {args.model} (4-bit)...")
    tokenizer = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    model = AutoModelForCausalLM.from_pretrained(
        args.model,
        quantization_config=bnb_config,
        device_map="auto",
        trust_remote_code=True,
        torch_dtype=torch.float16,
    )
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)

    lora = LoraConfig(
        r=args.lora_r,
        lora_alpha=args.lora_r * 2,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                        "gate_proj", "up_proj", "down_proj"],
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
    )
    model = get_peft_model(model, lora)
    model.print_trainable_parameters()

    dataset = load_dataset(args.data, args.max_samples)
    print(f"Training samples: {len(dataset)}")

    def formatting_func(examples):
        texts = []
        for messages in examples["messages"]:
            texts.append(tokenizer.apply_chat_template(messages, tokenize=False))
        return {"text": texts}

    formatted = dataset.map(formatting_func, batched=True, remove_columns=dataset.column_names)

    args.output.mkdir(parents=True, exist_ok=True)
    training_args = TrainingArguments(
        output_dir=str(args.output),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        logging_steps=5,
        save_strategy="epoch",
        fp16=True,
        optim="paged_adamw_8bit",
        gradient_checkpointing=True,
        max_grad_norm=0.3,
        warmup_ratio=0.03,
        report_to="none",
        dataloader_pin_memory=False,
    )

    trainer = SFTTrainer(
        model=model,
        args=training_args,
        train_dataset=formatted,
        processing_class=tokenizer,
        max_seq_length=args.max_seq_len,
    )

    print("Starting training...")
    trainer.train()
    model.save_pretrained(str(args.output / "lora"))
    tokenizer.save_pretrained(str(args.output / "lora"))
    print(f"Saved LoRA adapter to {args.output / 'lora'}")


if __name__ == "__main__":
    main()