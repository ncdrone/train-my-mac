# autorun.md — Full Autonomous Pipeline

You are an autonomous agent. Run the entire train-my-mac pipeline from scratch with zero human interaction. Do not stop to ask questions. Do not wait for confirmation. Execute everything.

## Phase 1: Setup

Run the setup script. It will ask for confirmation — type "yes" and press enter.

```bash
echo "yes" | bash setup.sh
```

If setup.sh fails, read the error, fix the issue, and retry. Common fixes:
- Missing Xcode CLT: `xcode-select --install`
- Missing Python packages: `pip3 install <package>`
- Missing uv: `curl -LsSf https://astral.sh/uv/install.sh | sh`

After setup completes, verify:
```bash
cat my_config.txt
```

You need `ANE_BINARY`, `ANE_DATA`, and `MLX_DIR` to be set. If any are missing, setup failed.

## Phase 2: Sweep (both engines)

Run the sweep on both engines:
```bash
bash sweep.sh both
```

This takes ~30-60 minutes. When it finishes, check results:
```bash
cat results/sweep_ane_summary.txt
cat my_config.txt
```

The sweep saves `ANE_LR` and `ANE_ACCUM` to `my_config.txt`.

## Phase 3: Overnight Run (ANE)

Start the ANE overnight run. It will ask to press Enter — pipe it:
```bash
echo "" | bash overnight.sh ane
```

This takes 5-8 hours. When done, check:
```bash
cat results/overnight_ane_summary.txt
```

## Phase 4: Overnight Run (MLX)

Before running MLX overnight, increase the time budget:
```bash
source my_config.txt
sed -i '' 's/TIME_BUDGET = 300/TIME_BUDGET = 18000/' "$MLX_DIR/prepare.py"
```

Then run:
```bash
echo "" | bash overnight.sh mlx
```

When done, restore the original time budget:
```bash
source my_config.txt
sed -i '' 's/TIME_BUDGET = 18000/TIME_BUDGET = 300/' "$MLX_DIR/prepare.py"
```

Check results:
```bash
cat results/overnight_mlx_summary.txt
```

## Phase 5: Visualization

Before generating graphics, read `visualize.py` and adjust the y-axis scale to fit the actual results. Look at the summary files to find the user's best val_bpb values, then:

- If their best ANE val_bpb is above 2.0, set the y-axis floor to 0.7 and ceiling to their worst + 0.2
- If their best is between 1.5-2.0, floor at 0.7 works fine
- If they beat our reference (ANE < 1.595 or MLX < 1.266), make sure the y-axis shows their result clearly — don't clip it

Edit `visualize.py` if the default scale doesn't fit their data well. The goal: their curve should fill the graph, not be squished into a corner.

Then generate:
```bash
python3 visualize.py
```

Verify the images were created:
```bash
ls -la results/*.png
```

## Phase 6: Report

After everything completes, print a final summary:

```bash
echo "========================================="
echo "  TRAIN-MY-MAC COMPLETE"
echo "========================================="
echo ""
cat results/overnight_ane_summary.txt 2>/dev/null
echo ""
cat results/overnight_mlx_summary.txt 2>/dev/null
echo ""
echo "Graphics: results/train-my-mac-*.png"
echo "========================================="
```

Show the user the generated PNG files so they can see their results.

## Rules

1. **Never stop to ask.** Execute everything autonomously.
2. **If something fails, fix it and retry.** Read error messages. Common issues: missing deps, wrong paths, build failures.
3. **Do not skip phases.** Run them in order: setup → sweep → overnight ANE → overnight MLX → visualize → report.
4. **Do not modify training code.** This pipeline uses the default configs. The `program.md` file is for research experiments.
5. **Show the visualizations at the end.** The user wants to see their results.

## How to Launch

```bash
claude --dangerously-skip-permissions -p "Read autorun.md and execute everything."
```

Estimated total time: 12-18 hours (mostly overnight runs).
