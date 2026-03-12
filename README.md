# train-my-mac

Train a GPT on your Mac. For real.

Not inference. Not fine-tuning someone else's model. Training from scratch.

Two accelerators. One chip. Your Mac.

- **ANE** (Apple Neural Engine) — native Obj-C, private APIs, 38 TOPS
- **MLX** (Apple's ML framework) — native Python, bf16, GPU

Both run simultaneously. Zero interference.
They talk to each other through a gossip system.
Results from one inform the other.

Same dataset as Karpathy's original autoresearch (climbmix-400B).
Same tokenizer (rustbpe, vocab=8192).
Same metric (val_bpb).
**Your results are directly comparable to NVIDIA H100 runs.**

We ran 400+ experiments on an M4 Max 128GB.
Now you can run yours.

---

## The Warning

The ANE path uses Apple's **private** `AppleNeuralEngine.framework` via `dlopen`.

- Undocumented. Unsupported. May violate Apple's Terms of Service.
- Could break on any macOS update.
- No warranty. No guarantees.

The MLX path uses Apple's public ML framework. No private APIs.

Your Mac. Your risk.

---

## Hardware Requirements

| Tier | Memory | Examples | What You Get |
|------|--------|---------|--------------|
| Minimum | 16 GB | M1, M2, M3 base | MLX only. ANE light preset. |
| Recommended | 24-36 GB | M2 Pro, M3 Pro, M4 Pro | Both accelerators. Standard config. |
| Ideal | 48-128 GB | M3 Max, M4 Max | Full config. Fast steps. Gossip. |
| Beast | 192 GB | M4 Ultra | Untested. You tell us. |

Below 16GB: not supported.

---

## Getting Started

```bash
git clone https://github.com/ncdrone/train-my-mac.git
cd train-my-mac
bash setup.sh
```

The setup script will:
1. Check your hardware and recommend a tier
2. Clone the training repos into `engines/` (ANE + MLX — not included in this repo)
3. Install dependencies
4. Download the Karpathy climbmix-400B dataset (~500 MB)
5. Build the native ANE binary
6. Set up the MLX environment
7. Run smoke tests on both accelerators

Then:
```bash
bash sweep.sh         # Find your best config (~30 min per accelerator)
bash overnight.sh     # Full training run (~5-8 hours)
bash overnight.sh mlx # Or train on MLX instead
bash gossip.sh        # Run both with gossip (advanced)
```

---

## What We Did

We built an autonomous research loop on Apple Silicon.

An AI agent modifies training code.
Runs a 5-minute experiment.
Evaluates `val_bpb` (validation bits per byte — lower is better).
Keeps the change if it improved. Discards if it didn't.
Repeats overnight.

400+ experiments. Three accelerators. One M4 Max 128GB.

**ANE best:** val_bpb = 1.595 (72K steps, 8.2 hours, native Obj-C)
**MLX best:** val_bpb = 1.266 (Muon + AdamW optimizer, 259 experiments)

The gap between them? That's where the research is.

---

## The Methodology

This is how we approached it. Use it as a starting point.

**Change one thing at a time.**
If you change LR and warmup simultaneously and it improves, you don't know which helped.

**5-minute runs are for screening, not conclusions.**
They tell you what's promising. The overnight run tells you the truth.

**val_bpb is the only metric that matters.**
Training loss can lie (overfitting). Validation bits-per-byte on held-out data is ground truth. Lower is better.

**Think in relative terms.**
Going from 2.0 to 1.8 is huge. Going from 1.60 to 1.59 might not be worth added complexity.

**When things explode, that's data.**
Activation magnitudes above 50 mean something is wrong. But knowing *when* it explodes tells you about stability boundaries.

**Simpler code wins.**
If you can remove code and get the same val_bpb, that's a great outcome.

**Log everything.**
You will want to go back and compare.

---

## The Two Engines

### ANE (Apple Neural Engine)

Native Obj-C. Uses private `AppleNeuralEngine.framework` APIs.
Weights packed into IOSurface inputs. Kernels compile once at startup.
Weight updates are just memcpy. No recompilation.

- 48.8M param GPT (NL=6, SEQ=512, DIM=768)
- ~80-100ms/step on M4 Max
- Invisible to Activity Monitor
- Best: val_bpb = 1.595

### MLX (Apple's ML Framework)

Python. Apple's native ML framework, purpose-built for Apple Silicon.
Native bf16. Unified memory. Muon + AdamW optimizer.

- 15.7M param GPT (optimized architecture)
- Native bf16 (unlike MPS where it was 2.6x slower)
- Best: val_bpb = 1.266

### Gossip System

Both engines write results to a shared JSONL file.
Each agent reads the other's experiments before planning its next one.
Cross-pollination: ANE discoveries inform MLX experiments and vice versa.

The shared file lives at `~/.cache/autoresearch/gossip/shared_experiments.jsonl`.

---

## Phase 1: The Sweep (~30 min per engine)

`sweep.sh` runs short experiments to find what works on your hardware.

**What it tests:**
- Learning rate: 1e-4, 2.5e-4, 5e-4, 1e-3
- Gradient accumulation: 1 vs 2

Each experiment runs for 5 minutes. The winning config is saved.

```bash
bash sweep.sh         # sweep ANE (default)
bash sweep.sh mlx     # sweep MLX
bash sweep.sh both    # sweep both (1 hour total)
```

---

## Phase 2: The Overnight Run

`overnight.sh` runs 72K steps with your discovered config.

```bash
bash overnight.sh           # ANE overnight
bash overnight.sh mlx       # MLX overnight
bash overnight.sh --lr 5e-4 # override config
```

When it finishes, `visualize.py` generates a results graphic comparing your run to our research.

---

## Phase 3: Gossip (Advanced)

Run both engines simultaneously with the gossip system active.
Each engine checks the other's results every 100 steps.

```bash
bash gossip.sh    # launches ANE + MLX in parallel with shared gossip
```

This is how we got our best results. ANE found that eps=1e-10 helps.
MLX found that Muon optimizer dominates. Cross-pollination compounds.

---

## What Success Looks Like

After the sweep: you know your best config, val_bpb under 2.5.

After overnight:
- ANE: val_bpb under 1.8, possibly under 1.7
- MLX: val_bpb under 1.4 with Muon

Our bests:
- ANE: **1.595** (M4 Max 128GB)
- MLX: **1.266** (M4 Max 128GB)

Getting within 0.1-0.2 of those on lesser hardware is a great result.

---

## Going Further

**Modify the training code.** ANE: `engines/autoresearch-ANE/native/training/train.m`. MLX: `engines/autoresearch-mlx/train.py`. Change something, run 5 minutes, see what happens.

**DO NOT RUN THIS (unless you're crazy).**
Let Claude do everything for you. Setup, sweep, overnight, visualize — fully autonomous. You walk away. It trains your Mac overnight. You wake up to results.
```bash
claude --dangerously-skip-permissions -p "Read autorun.md and execute everything."
```

**Autonomous research mode.** Claude modifies training code, runs experiments, keeps what works, discards what doesn't. Loops forever.
```bash
claude --dangerously-skip-permissions -p "Read program.md and start autoresearch."
```

**Explore what we haven't tried.** See `engines/autoresearch-ANE/docs/ideas/roadmap_unexplored.md`. ANE classifier on-chip, Muon optimizer port, bf16, kernel fusion.

**Community leaderboard.** (Coming soon.) Submit your results. See what every Mac can do.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Build fails | `xcode-select --install` |
| "No ANE device found" | Intel Macs don't have ANE. M-series only. |
| Activations explode (x > 50) | Lower LR by 2x |
| OOM / memory pressure | Use light preset or MLX only |
| Fans spinning hard | Normal. If ms/step climbs, thermal throttling — pause. |
| val_bpb plateaus | More steps. Model still improving at 40K+. |
| MLX: bf16 errors | Update MLX: `pip install -U mlx` |

---

## Credits

- [Andrej Karpathy](https://github.com/karpathy) — autoresearch concept and climbmix-400B dataset
- [maderix](https://github.com/maderix) — ANE private API reverse engineering
- [trevin-creator](https://github.com/trevin-creator) — MLX port
- [Apple MLX team](https://github.com/ml-explore/mlx)

## License

MIT
