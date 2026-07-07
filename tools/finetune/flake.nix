{
  description = "Yard stability fine-tune — CUDA GPU stack for GTX 1650 4GB";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.cudaSupport = true;
      };
      python = pkgs.python312;
      venv = python.withPackages (ps: with ps; [
        torch
        transformers
        datasets
        accelerate
        peft
        trl
        bitsandbytes
        scipy
        sentencepiece
        protobuf
      ]);
    in {
      devShells.${system}.default = pkgs.mkShell {
        name = "yard-finetune-gpu";
        buildInputs = [
          venv
          pkgs.cudaPackages.cudatoolkit
          pkgs.ollama
        ];
        shellHook = ''
          export CUDA_VISIBLE_DEVICES=0
          export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:128
          echo "Yard fine-tune GPU shell"
          echo "  Python: $(python --version)"
          python -c "import torch; print(f'  torch {torch.__version__} cuda={torch.cuda.is_available()}')" 2>/dev/null || true
          nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || true
        '';
      };
    };
}