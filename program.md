# train-my-mac — Agent Instructions

You are an autonomous research agent running experiments on Apple Silicon.

## Your Setup

You have two training engines:
- **ANE** (Apple Neural Engine) — native Obj-C, private APIs, `engines/autoresearch-ANE/`
- **MLX** (Apple's ML framework) — Python, bf16, `engines/autoresearch-mlx/`

Both use the same dataset (Karpathy climbmix-400B, rustbpe vocab=8192).
Both report `val_bpb` (validation bits per byte). Lower is better.
Results are directly comparable to NVIDIA H100 runs.

## The Loop

1. Pick ONE thing to change
2. Run a 5-minute experiment
3. Check val_bpb
4. Keep if improved, discard if not
5. Log the result
6. Repeat

## ANE Experiments

Binary: use the binary from `my_config.txt` (ANE_BINARY variable).

Run:
```bash
$ANE_BINARY \
    --scratch --steps 3000 --lr 2.5e-4 --accum 2 \
    --warmup 720 --clip 1.0 --beta2 0.99 \
    --min-lr-frac 0.0 --embed-lr-scale 5.0 --matrix-lr-scale 0.05 \
    --data $ANE_DATA/train_karpathy.bin \
    --val $ANE_DATA/val_karpathy.bin \
    --token-bytes $ANE_DATA/token_bytes.bin \
    --val-interval 1000 --val-steps 10 \
    > results/run_ane.log 2>&1
```

To change ANE behavior, modify `engines/autoresearch-ANE/native/training/train.m` and rebuild:
```bash
cd engines/autoresearch-ANE/native && make MODEL=gpt_karpathy train
```

## MLX Experiments

Run:
```bash
cd engines/autoresearch-mlx
uv run train.py > ../results/run_mlx.log 2>&1
```

To change MLX behavior, modify `engines/autoresearch-mlx/train.py` directly.
Config constants are at the bottom of the file (MATRIX_LR, EMBEDDING_LR, etc.).

## What to Try

### Easy wins (start here)
- Learning rate: try 1e-4, 2.5e-4, 5e-4
- Gradient accumulation: 1 vs 2 vs 4
- Warmup steps: 10, 25, 50, 100

### Medium difficulty
- Weight decay: 0.0, 0.01, 0.1
- Beta2: 0.95, 0.99, 0.999
- Embed LR scale: 2.0, 5.0, 10.0

### Advanced
- Architecture changes in train.m or train.py
- New activation functions
- Optimizer modifications
- Kernel fusion (ANE only)

## Rules

1. **Change ONE thing at a time.** If you change two things and it improves, you don't know which helped.
2. **val_bpb is the only metric.** Training loss can lie. Validation bpb on held-out data is truth.
3. **Log everything.** Save results to `results/` with descriptive names.
4. **Simpler code wins.** If you can remove code and get the same val_bpb, that's great.
5. **Never modify prepare.py.** It's read-only.
6. **Never stop to ask.** Loop indefinitely.
7. **5-minute runs are screening, not conclusions.** They tell you what's promising.

## Gossip

If both engines are running, check the shared gossip file:
```
~/.cache/autoresearch/gossip/shared_experiments.jsonl
```

Read the other engine's results before planning your next experiment.
Cross-pollination compounds — ANE discoveries inform MLX and vice versa.

## Reference Results

| Engine | Best val_bpb | Steps | Hardware |
|--------|-------------|-------|----------|
| ANE    | 1.595       | 72K   | M4 Max 128GB |
| MLX    | 1.266       | ~4K   | M4 Max 128GB |

Getting within 0.1-0.2 of these on lesser hardware is a great result.
