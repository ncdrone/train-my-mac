# train-my-mac

Train a GPT on your Mac.

Not inference. Not fine-tuning someone else's model. Training from scratch.

## What This Is

Two accelerators. One chip. Your Mac.

- **ANE** (Apple Neural Engine) — native Obj-C, private APIs, 38 TOPS
- **MLX** (Apple's ML framework) — native Python, bf16, GPU

Same dataset as Karpathy's original autoresearch (climbmix-400B).
Same tokenizer (rustbpe, vocab=8192).
Same metric (val_bpb).
**Your results are directly comparable to NVIDIA H100 runs.**

We ran 400+ experiments on an M4 Max 128GB. Now you can run yours.

---

## Quick Start

Three commands. That's it.

```bash
git clone https://github.com/ncdrone/train-my-mac.git
cd train-my-mac
bash setup.sh
```

Setup does everything: checks your hardware, clones the engines, installs dependencies, downloads the dataset (~500 MB), builds the native ANE binary, and runs smoke tests on both accelerators.

When it finishes, train:

```bash
bash sweep.sh         # find your best config (~30 min)
bash overnight.sh     # full ANE training run (~5-8 hours)
bash overnight.sh mlx # or train on MLX instead
bash gossip.sh        # run both engines simultaneously (advanced)
```

Skip all prompts with `--yes`:

```bash
bash setup.sh --yes
```

### Requirements

- Apple Silicon Mac (M1 or later)
- 16 GB RAM minimum
- Xcode Command Line Tools (`xcode-select --install`)
- [uv](https://docs.astral.sh/uv/) (auto-installed if missing)

### Hardware Tiers

| Tier | Memory | Examples | What You Get |
|------|--------|---------|--------------|
| Minimum | 16 GB | M1, M2, M3 base, M5 Air | MLX only. ANE light preset. |
| Okay | 24-36 GB | M2 Pro, M3 Pro, M4 Pro | Both accelerators. Standard config. |
| Recommended | 48-128 GB | M3/M4 Max, M5 Max | Full config. Fast steps. Gossip. |
| Ideal | 128+ GB | M3 Ultra (256 GB), M5 Ultra | The setup. You tell us. |

Below 16GB: not supported.

---

## What Setup Does

`bash setup.sh` runs six steps in order:

| Step | What | Details |
|------|------|---------|
| 1 | Hardware detection | Identifies your chip, memory, tier |
| 2 | Clone engines | ANE (native Obj-C) + MLX (Python) into `engines/` |
| 3 | Install dependencies | `uv sync` for both engines (isolated venvs) |
| 4 | Download data | Karpathy climbmix-400B, ~500 MB, tokenized |
| 5 | Build ANE binary | Compiles native training loop with Xcode CLT |
| 6 | Smoke tests | 50 steps on each engine to verify everything works |

Config is saved to `my_config.txt`. All subsequent scripts read from it.

---

## Training

### Phase 1: Sweep (~30 min per engine)

Short experiments to find what works on your hardware.

```bash
bash sweep.sh         # sweep ANE (default)
bash sweep.sh mlx     # sweep MLX
bash sweep.sh both    # sweep both (1 hour total)
```

Tests learning rates (1e-4, 2.5e-4, 5e-4, 1e-3) and gradient accumulation (1 vs 2). Each experiment runs 5 minutes. Best config is saved automatically.

### Phase 2: Overnight Run

Full training with your discovered config. Auto-launches in tmux so closing your terminal won't kill the run.

```bash
bash overnight.sh           # ANE overnight (72K steps, 5-8 hours)
bash overnight.sh mlx       # MLX overnight
bash overnight.sh --lr 5e-4 # override learning rate
bash overnight.sh --steps 10000  # shorter run
```

Reattach anytime: `tmux attach -t train-my-mac`

When it finishes, `visualize.py` generates a results graphic comparing your run to our research.

### Phase 3: Gossip (Advanced)

Both engines running simultaneously on the same chip. ANE on the Neural Engine, MLX on the GPU. Zero interference.

```bash
bash gossip.sh    # launches both in parallel with shared gossip
```

Each engine writes results to a shared JSONL file. Discoveries from one inform the other. This is how we got our best results.

---

## What Success Looks Like

![example results](results/train-my-mac.png)

After the sweep: you know your best config, val_bpb under 2.5.

After overnight:
- ANE: val_bpb under 1.8, possibly under 1.7
- MLX: val_bpb under 1.4 with Muon

Our bests:
- ANE: **1.595** (M4 Max 128GB, 72K steps, 8.2 hours)
- MLX: **1.266** (M4 Max 128GB, Muon + AdamW, 259 experiments)

Getting within 0.1-0.2 of those on lesser hardware is a great result.

---

## Cleanup

Remove everything setup created and start fresh.

```bash
bash clean.sh          # interactive — confirms before deleting
bash clean.sh --yes    # delete engines, config, and logs without prompting
bash clean.sh --all    # also delete cached dataset (~1 GB in ~/.cache/autoresearch)
```

What gets removed:

| `clean.sh` | `clean.sh --all` |
|------------|------------------|
| `engines/` (cloned repos, venvs, builds) | everything in the left column |
| `my_config.txt` | `~/.cache/autoresearch/` (dataset + tokenizer) |
| `results/*.log` and summaries | |

The sample result PNGs in `results/` are kept. Run `bash setup.sh` to rebuild everything.

---

## The Methodology

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

## Under the Hood

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

Both engines write results to a shared JSONL file at `~/.cache/autoresearch/gossip/shared_experiments.jsonl`. Each agent reads the other's experiments before planning its next one. Cross-pollination: ANE discoveries inform MLX experiments and vice versa.

### How We Got Here

We built an autonomous research loop on Apple Silicon. An AI agent modifies training code, runs a 5-minute experiment, evaluates val_bpb, keeps the change if it improved, discards if it didn't, and repeats overnight.

400+ experiments. Two accelerators. One M4 Max 128GB.

The gap between ANE and MLX? That's where the research is.

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
| MLX: bf16 errors | `uv sync` in `engines/autoresearch-mlx/` |
| Want a fresh start | `bash clean.sh --all` then `bash setup.sh` |

---

## Credits

- [Andrej Karpathy](https://github.com/karpathy) — autoresearch concept and climbmix-400B dataset
- [maderix](https://github.com/maderix) — ANE private API reverse engineering
- [trevin-creator](https://github.com/trevin-creator) — MLX port
- [Apple MLX team](https://github.com/ml-explore/mlx)

---

## Warning

The ANE engine uses Apple's **private** `AppleNeuralEngine.framework` via `dlopen`. This means:

- **Undocumented.** There is no official API reference. The interface was reverse-engineered.
- **Unsupported.** Apple does not support third-party use of this framework.
- **May violate Apple's Terms of Service.** Using private frameworks is explicitly discouraged by Apple and may breach the macOS EULA.
- **Could break on any macOS update.** Apple can change or remove the private API at any time without notice.
- **No warranty.** This software is provided as-is. No guarantees of correctness, safety, or fitness for any purpose.
- **Could stress your hardware.** Long training runs push the Neural Engine, GPU, and thermal system continuously for hours. Monitor your temps.

The MLX engine uses Apple's **public** ML framework. No private APIs. No risk beyond normal GPU compute.

**You are responsible for what runs on your machine.** If you are not comfortable with these risks, use `bash sweep.sh mlx` and `bash overnight.sh mlx` to run only the MLX engine.

## License

MIT — no warranty, no liability, use at your own risk.
