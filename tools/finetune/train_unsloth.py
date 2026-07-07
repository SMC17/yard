#!/usr/bin/env python3
"""
QLoRA fine-tune yard-stability behavior with Unsloth.

Hardware note: GTX 1650 4GB is too small for 7B QLoRA.
Minimum recommended: 12GB VRAM for Qwen2.5-3B QLoRA.
Run on cloud GPU or Mac/CUDA workstation with >= 12GB.

Usage:
  pip install unsloth transformers datasets trl peft
  python train_unsloth.py --data ../dataset/out/train_chat.jsonl --output ../../models/yard-stability-v1

Requires CUDA. Will exit gracefully on CPU-only systems.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def check_cuda() -> bool:
    try:
        import torch
        return torch.cuda.is_available()
    except ImportError:
        return False


def load_chat_dataset(path: Path):
    from datasets import Dataset

    records = []
    with path.open() as f:
        for line in f:
            records.append(json.loads(line))
    return Dataset.from_list(records)


def main() -> None:
    parser = argparse.ArgumentParser(description="Unsloth QLoRA fine-tune for yard stability")
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("models/yard-stability-v1"))
    parser.add_argument("--model", default="unsloth/Qwen2.5-3B-Instruct-bnb-4bit")
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--max-seq-len", type=int, default=2048)
    parser.add_argument("--batch-size", type=int, default=2)
    parser.add_argument("--grad-accum", type=int, default=4)
    args = parser.parse_args()

    if not check_cuda():
        print("ERROR: CUDA not available. This script requires a GPU with >= 12GB VRAM.", file=sys.stderr)
        print("Export your dataset and run on a cloud GPU (Lambda, RunPod, Colab Pro).", file=sys.stderr)
        print(f"Dataset ready at: {args.data}", file=sys.stderr)
        sys.exit(1)

    from unsloth import FastLanguageModel
    from trl import SFTTrainer
    from transformers import TrainingArguments

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model,
        max_seq_length=args.max_seq_len,
        load_in_4bit=True,
    )
    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                        "gate_proj", "up_proj", "down_proj"],
        lora_alpha=16,
        lora_dropout=0.05,
        bias="none",
    )

    dataset = load_chat_dataset(args.data)

    def formatting_func(examples):
        texts = []
        for messages in examples["messages"]:
            text = tokenizer.apply_chat_template(messages, tokenize=False)
            texts.append(text)
        return {"text": texts}

    formatted = dataset.map(formatting_func, batched=True)

    training_args = TrainingArguments(
        output_dir=str(args.output),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        logging_steps=10,
        save_strategy="epoch",
        fp16=True,
        report_to="none",
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=formatted,
        dataset_text_field="text",
        max_seq_length=args.max_seq_len,
        args=training_args,
    )

    print(f"Training on {len(formatted)} records...")
    trainer.train()
    model.save_pretrained(str(args.output / "lora"))
    tokenizer.save_pretrained(str(args.output / "lora"))
    print(f"Saved LoRA adapter to {args.output / 'lora'}")


if __name__ == "__main__":
    main()