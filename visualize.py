"""Generate shareable results graphics — your Mac vs our research.
Auto-detects what you ran and generates the right graphic.

Three modes:
  1. Experiments — 100 x 5-min runs (like Karpathy). X = experiment #.
  2. Overnight  — one long training run. X = steps.
  3. Agent Gossip — 100 x 5-min runs, both engines. X = experiment #, two curves.

Usage: python3 visualize.py
Outputs to results/ and copies to ~/Desktop."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
import os
import re
import shutil
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")
SHARE_DIR = os.path.expanduser("~/Desktop")

c = {
    "bg":     "#0c0c14",
    "card":   "#13131f",
    "grid":   "#181826",
    "ane":    "#79c0ff",
    "mlx":    "#ff79c6",
    "accent": "#e3b341",
    "green":  "#56d364",
    "white":  "#c9d1d9",
    "dim":    "#8b949e",
    "dimmer": "#484f58",
}
FONT = "monospace"


# ─── Parsers ──────────────────────────────────────────────────────────────────

def parse_step_log(log_path):
    """Parse overnight logs: step N val_bpb=X.XXX"""
    checkpoints = []
    with open(log_path) as f:
        for line in f:
            val_match = re.search(r"val_bpb[=: ]+(\d+\.\d+)", line)
            step_match = re.search(r"step\s+(\d+)", line)
            if val_match and step_match:
                checkpoints.append((int(step_match.group(1)), float(val_match.group(1))))
    return checkpoints


def parse_experiment_log(log_path):
    """Parse experiment logs: one val_bpb per experiment.
    Handles formats:
      experiment 1 val_bpb=2.543
      exp 1: val_bpb 2.543
      val_bpb=2.543  (just numbered by line)
    Returns list of (experiment_num, val_bpb)."""
    results = []
    with open(log_path) as f:
        for i, line in enumerate(f):
            val_match = re.search(r"val_bpb[=: ]+(\d+\.\d+)", line)
            if val_match:
                exp_match = re.search(r"(?:exp(?:eriment)?)\s*(\d+)", line, re.IGNORECASE)
                exp_num = int(exp_match.group(1)) if exp_match else len(results) + 1
                results.append((exp_num, float(val_match.group(1))))
    return results


def parse_summary(path):
    info = {}
    if not os.path.exists(path):
        return info
    with open(path) as f:
        for line in f:
            if "=" in line:
                key, val = line.strip().split("=", 1)
                info[key] = val
    return info


# ─── Helpers ──────────────────────────────────────────────────────────────────

def get_hardware_info():
    try:
        chip = subprocess.check_output(
            ["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    except Exception:
        chip = "Unknown"
    try:
        mem_bytes = int(subprocess.check_output(
            ["sysctl", "-n", "hw.memsize"], text=True).strip())
        mem_gb = mem_bytes // (1024**3)
    except Exception:
        mem_gb = 0
    return chip, mem_gb


def share(src_path):
    filename = os.path.basename(src_path)
    dest = os.path.join(SHARE_DIR, filename)
    shutil.copy2(src_path, dest)
    print(f"  Copied to ~/Desktop/{filename}")


def gap_text(theirs, ours):
    try:
        gap = float(theirs) - float(ours)
        if gap <= 0:
            return f"BEAT IT by {abs(gap):.3f}", c["green"]
        elif gap < 0.1:
            return f"within {gap:.3f}", c["green"]
        else:
            return f"gap: {gap:.3f}", c["accent"]
    except (ValueError, TypeError):
        return None, None


def style_ax(ax):
    ax.set_facecolor(c["bg"])
    ax.tick_params(colors=c["dim"], labelsize=7)
    ax.spines["bottom"].set_color(c["dimmer"])
    ax.spines["left"].set_color(c["dimmer"])
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="y", color=c["grid"], linewidth=0.5)
    for label in ax.get_xticklabels() + ax.get_yticklabels():
        label.set_fontfamily(FONT)


def draw_card(fig, x, y, w, h, color, label, bpb, detail, ref_bpb, ref_label):
    card = FancyBboxPatch((x, y), w, h,
                           boxstyle="round,pad=0.02", facecolor=c["card"],
                           edgecolor=color, linewidth=2.5,
                           transform=fig.transFigure)
    fig.patches.append(card)
    cx = x + w / 2

    fig.text(cx, y + h - 0.03, label,
             fontsize=11, fontweight="bold", color=color,
             ha="center", fontfamily=FONT)

    if bpb and bpb != "N/A":
        fig.text(cx, y + h * 0.55, bpb,
                 fontsize=30, fontweight="bold", color=c["white"],
                 ha="center", va="center", fontfamily=FONT)
    else:
        fig.text(cx, y + h * 0.55, "---",
                 fontsize=30, fontweight="bold", color=c["dimmer"],
                 ha="center", va="center", fontfamily=FONT)

    text, gcolor = gap_text(bpb, ref_bpb)
    if text:
        fig.text(cx, y + h * 0.30, text,
                 fontsize=10, fontweight="bold", color=gcolor,
                 ha="center", fontfamily=FONT)

    fig.text(cx, y + h * 0.17, f"ref: {ref_bpb}  ({ref_label})",
             fontsize=7, color=c["dimmer"], ha="center", fontfamily=FONT)

    fig.text(cx, y + h * 0.06, detail,
             fontsize=6.5, color=c["dimmer"], ha="center", fontfamily=FONT)


def save_and_share(fig, name):
    out_path = os.path.join(RESULTS_DIR, f"{name}.png")
    plt.savefig(out_path, dpi=200, facecolor=c["bg"], edgecolor="none", bbox_inches="tight")
    plt.close()
    print(f"  Saved to {out_path}")
    share(out_path)
    return out_path


def footer(fig):
    fig.text(0.5, 0.06,
             "same data as Karpathy  |  val_bpb comparable to H100  |  "
             "github.com/ncdrone/train-my-mac  |  made by @danpacary",
             fontsize=7.5, color=c["dimmer"], ha="center", fontfamily=FONT)


# ─── Graph drawers ────────────────────────────────────────────────────────────

def draw_curve(ax, xs, ys, color, label, xlabel):
    """Draw a single curve with best-value annotation and reference lines."""
    ax.plot(xs, ys, "o-", color=color, linewidth=2.5, markersize=5, zorder=3, label=label)
    best_i = ys.index(min(ys))
    ax.annotate(f"{ys[best_i]:.3f}",
                xy=(xs[best_i], ys[best_i]),
                xytext=(12, 10), textcoords="offset points",
                fontsize=12, fontweight="bold", color=color, fontfamily=FONT,
                arrowprops=dict(arrowstyle="->", color=color, lw=1.5))
    ax.set_xlabel(xlabel, fontsize=7, color=c["dim"], fontfamily=FONT)
    ax.set_ylabel("val_bpb", fontsize=7, color=c["dim"], fontfamily=FONT)


def add_ref_lines(ax, engine_color, ref_bpb, ref_label):
    """Add our-best and Karpathy reference lines."""
    xlim = ax.get_xlim()
    ax.axhline(y=ref_bpb, color=engine_color, linewidth=1.5, linestyle=":", alpha=0.7)
    ax.text(xlim[0] + (xlim[1] - xlim[0]) * 0.02, ref_bpb - 0.07,
            ref_label, fontsize=7, color=engine_color, fontfamily=FONT, alpha=0.8)
    ax.axhline(y=0.8, color=c["accent"], linewidth=1, linestyle="--", alpha=0.5)
    ax.text(xlim[0] + (xlim[1] - xlim[0]) * 0.02, 0.83,
            "Karpathy H100", fontsize=6, color=c["accent"], fontfamily=FONT, alpha=0.6)


# ─── 1. Experiments (100 x 5-min, like Karpathy) ─────────────────────────────

def generate_experiments(chip_display, their_mem):
    """Graph experiment results. X = experiment number."""
    # Check for experiment logs (ANE or MLX)
    ane_path = os.path.join(RESULTS_DIR, "sweep_ane.log")
    mlx_path = os.path.join(RESULTS_DIR, "sweep_mlx.log")
    ane_exp = parse_experiment_log(ane_path) if os.path.exists(ane_path) else []
    mlx_exp = parse_experiment_log(mlx_path) if os.path.exists(mlx_path) else []

    has_ane = len(ane_exp) >= 2
    has_mlx = len(mlx_exp) >= 2
    if not has_ane and not has_mlx:
        return None

    fig = plt.figure(figsize=(10, 10), facecolor=c["bg"])
    fig.text(0.5, 0.965, "train-my-mac",
             fontsize=26, fontweight="bold", color=c["white"],
             ha="center", fontfamily=FONT)
    fig.text(0.5, 0.935, f"{chip_display}  |  {their_mem} GB  |  5-min experiments",
             fontsize=10, color=c["dim"], ha="center", fontfamily=FONT)

    if has_ane and has_mlx:
        ax_ane = fig.add_axes([0.07, 0.56, 0.42, 0.33])
        xs, ys = zip(*ane_exp)
        draw_curve(ax_ane, list(xs), list(ys), c["green"], "yours", "experiment")
        add_ref_lines(ax_ane, c["ane"], 1.5949, "@danpacary: 1.595 (M4 Max)")
        ax_ane.set_ylim(0.7, max(ys) + 0.15)
        ax_ane.legend(loc="upper right", fontsize=7, facecolor=c["card"],
                     edgecolor=c["dimmer"], labelcolor=c["white"], prop={"family": FONT})
        style_ax(ax_ane)
        ax_ane.set_title("NEURAL ENGINE", fontsize=11, fontweight="bold",
                        color=c["ane"], fontfamily=FONT, pad=8)

        ax_mlx = fig.add_axes([0.56, 0.56, 0.42, 0.33])
        xs, ys = zip(*mlx_exp)
        draw_curve(ax_mlx, list(xs), list(ys), c["green"], "yours", "experiment")
        add_ref_lines(ax_mlx, c["mlx"], 1.2661, "@danpacary: 1.266 (M4 Max)")
        ax_mlx.set_ylim(0.7, max(ys) + 0.15)
        ax_mlx.legend(loc="upper right", fontsize=7, facecolor=c["card"],
                     edgecolor=c["dimmer"], labelcolor=c["white"], prop={"family": FONT})
        style_ax(ax_mlx)
        ax_mlx.set_title("MLX GPU", fontsize=11, fontweight="bold",
                        color=c["mlx"], fontfamily=FONT, pad=8)

        ane_best = f"{min(v for _, v in ane_exp):.3f}"
        mlx_best = f"{min(v for _, v in mlx_exp):.3f}"
        draw_card(fig, 0.07, 0.18, 0.42, 0.28,
                 c["ane"], "NEURAL ENGINE", ane_best,
                 f"native Obj-C  |  {len(ane_exp)} experiments  |  5 min each",
                 "1.595", "M4 Max 128GB")
        draw_card(fig, 0.56, 0.18, 0.42, 0.28,
                 c["mlx"], "MLX GPU", mlx_best,
                 f"MLX bf16  |  {len(mlx_exp)} experiments  |  5 min each",
                 "1.266", "M4 Max 128GB")
    else:
        exp = ane_exp if has_ane else mlx_exp
        engine_color = c["ane"] if has_ane else c["mlx"]
        engine_name = "NEURAL ENGINE" if has_ane else "MLX GPU"
        ref_bpb = 1.5949 if has_ane else 1.2661
        ref_str = "1.595" if has_ane else "1.266"

        ax = fig.add_axes([0.10, 0.45, 0.85, 0.44])
        xs, ys = zip(*exp)
        draw_curve(ax, list(xs), list(ys), c["green"], "yours", "experiment")
        add_ref_lines(ax, engine_color, ref_bpb, f"@danpacary: {ref_str} (M4 Max)")
        ax.set_ylim(0.7, max(ys) + 0.15)
        ax.legend(loc="upper right", fontsize=7, facecolor=c["card"],
                 edgecolor=c["dimmer"], labelcolor=c["white"], prop={"family": FONT})
        style_ax(ax)
        ax.set_title(engine_name, fontsize=13, fontweight="bold",
                    color=engine_color, fontfamily=FONT, pad=10)

        best = f"{min(v for _, v in exp):.3f}"
        draw_card(fig, 0.15, 0.14, 0.70, 0.22,
                 engine_color, engine_name, best,
                 f"{len(exp)} experiments  |  5 min each",
                 ref_str, "M4 Max 128GB")

    footer(fig)
    return save_and_share(fig, "train-my-mac-experiments")


# ─── 2. Overnight (one long run, steps) ──────────────────────────────────────

def generate_overnight(chip_display, their_mem):
    """Graph overnight training. X = steps."""
    ane_log = os.path.join(RESULTS_DIR, "overnight_ane.log")
    mlx_log = os.path.join(RESULTS_DIR, "overnight_mlx.log")
    ane_cp = parse_step_log(ane_log) if os.path.exists(ane_log) else []
    mlx_cp = parse_step_log(mlx_log) if os.path.exists(mlx_log) else []

    has_ane = len(ane_cp) >= 2
    has_mlx = len(mlx_cp) >= 2
    if not has_ane and not has_mlx:
        return None

    ane_summary = parse_summary(os.path.join(RESULTS_DIR, "overnight_ane_summary.txt"))
    mlx_summary = parse_summary(os.path.join(RESULTS_DIR, "overnight_mlx_summary.txt"))

    fig = plt.figure(figsize=(10, 10), facecolor=c["bg"])
    fig.text(0.5, 0.965, "train-my-mac",
             fontsize=26, fontweight="bold", color=c["white"],
             ha="center", fontfamily=FONT)
    subtitle = f"{chip_display}  |  {their_mem} GB"
    if has_ane and has_mlx:
        subtitle += "  |  two accelerators, one chip"
    fig.text(0.5, 0.935, subtitle,
             fontsize=10, color=c["dim"], ha="center", fontfamily=FONT)

    if has_ane and has_mlx:
        ax_ane = fig.add_axes([0.07, 0.56, 0.42, 0.33])
        steps, bpb = zip(*ane_cp)
        draw_curve(ax_ane, list(steps), list(bpb), c["green"], "yours", "steps")
        add_ref_lines(ax_ane, c["ane"], 1.5949, "@danpacary: 1.595 (M4 Max)")
        ax_ane.set_ylim(0.7, max(bpb) + 0.15)
        ax_ane.legend(loc="upper right", fontsize=7, facecolor=c["card"],
                     edgecolor=c["dimmer"], labelcolor=c["white"], prop={"family": FONT})
        style_ax(ax_ane)
        ax_ane.set_title("NEURAL ENGINE", fontsize=11, fontweight="bold",
                        color=c["ane"], fontfamily=FONT, pad=8)

        ax_mlx = fig.add_axes([0.56, 0.56, 0.42, 0.33])
        steps, bpb = zip(*mlx_cp)
        draw_curve(ax_mlx, list(steps), list(bpb), c["green"], "yours", "steps")
        add_ref_lines(ax_mlx, c["mlx"], 1.2661, "@danpacary: 1.266 (M4 Max)")
        ax_mlx.set_ylim(0.7, max(bpb) + 0.15)
        ax_mlx.legend(loc="upper right", fontsize=7, facecolor=c["card"],
                     edgecolor=c["dimmer"], labelcolor=c["white"], prop={"family": FONT})
        style_ax(ax_mlx)
        ax_mlx.set_title("MLX GPU", fontsize=11, fontweight="bold",
                        color=c["mlx"], fontfamily=FONT, pad=8)

        ane_bpb = ane_summary.get("val_bpb", f"{min(v for _, v in ane_cp):.3f}")
        ane_hours = ane_summary.get("wall_hours", "")
        ane_steps = ane_summary.get("steps", str(ane_cp[-1][0]))
        ane_detail = f"native Obj-C  |  48.8M params  |  {ane_steps} steps"
        if ane_hours:
            ane_detail += f"  |  {ane_hours}h"

        mlx_bpb = mlx_summary.get("val_bpb", f"{min(v for _, v in mlx_cp):.3f}")
        mlx_hours = mlx_summary.get("wall_hours", "")
        mlx_detail = f"MLX bf16  |  15.7M params  |  Muon+AdamW"
        if mlx_hours:
            mlx_detail += f"  |  {mlx_hours}h"

        draw_card(fig, 0.07, 0.18, 0.42, 0.28,
                 c["ane"], "NEURAL ENGINE", ane_bpb, ane_detail,
                 "1.595", "M4 Max 128GB")
        draw_card(fig, 0.56, 0.18, 0.42, 0.28,
                 c["mlx"], "MLX GPU", mlx_bpb, mlx_detail,
                 "1.266", "M4 Max 128GB")
    else:
        cp = ane_cp if has_ane else mlx_cp
        summary = ane_summary if has_ane else mlx_summary
        engine_color = c["ane"] if has_ane else c["mlx"]
        engine_name = "NEURAL ENGINE" if has_ane else "MLX GPU"
        ref_bpb = 1.5949 if has_ane else 1.2661
        ref_str = "1.595" if has_ane else "1.266"

        ax = fig.add_axes([0.10, 0.45, 0.85, 0.44])
        steps, bpb = zip(*cp)
        draw_curve(ax, list(steps), list(bpb), c["green"], "yours", "steps")
        add_ref_lines(ax, engine_color, ref_bpb, f"@danpacary: {ref_str} (M4 Max)")
        ax.set_ylim(0.7, max(bpb) + 0.15)
        ax.legend(loc="upper right", fontsize=7, facecolor=c["card"],
                 edgecolor=c["dimmer"], labelcolor=c["white"], prop={"family": FONT})
        style_ax(ax)
        ax.set_title(engine_name, fontsize=13, fontweight="bold",
                    color=engine_color, fontfamily=FONT, pad=10)

        bpb_val = summary.get("val_bpb", f"{min(v for _, v in cp):.3f}")
        hours = summary.get("wall_hours", "")
        if has_ane:
            step_count = summary.get("steps", str(cp[-1][0]))
            detail = f"native Obj-C  |  48.8M params  |  {step_count} steps"
        else:
            detail = f"MLX bf16  |  15.7M params  |  Muon+AdamW"
        if hours:
            detail += f"  |  {hours}h"
        draw_card(fig, 0.15, 0.14, 0.70, 0.22,
                 engine_color, engine_name, bpb_val, detail,
                 ref_str, "M4 Max 128GB")

    footer(fig)
    return save_and_share(fig, "train-my-mac-overnight")


# ─── 3. Agent Gossip (both engines, experiments) ─────────────────────────────

def generate_gossip(chip_display, their_mem):
    """Graph agent gossip. Both engines on one graph. X = experiment number."""
    ane_path = os.path.join(RESULTS_DIR, "gossip_ane.log")
    mlx_path = os.path.join(RESULTS_DIR, "gossip_mlx.log")
    ane_exp = parse_experiment_log(ane_path) if os.path.exists(ane_path) else []
    mlx_exp = parse_experiment_log(mlx_path) if os.path.exists(mlx_path) else []

    if len(ane_exp) < 2 or len(mlx_exp) < 2:
        return None

    fig = plt.figure(figsize=(10, 10), facecolor=c["bg"])
    fig.text(0.5, 0.965, "AGENT GOSSIP",
             fontsize=26, fontweight="bold", color=c["accent"],
             ha="center", fontfamily=FONT)
    fig.text(0.5, 0.935, f"{chip_display}  |  {their_mem} GB  |  both engines, shared intelligence",
             fontsize=10, color=c["dim"], ha="center", fontfamily=FONT)

    # One big graph — both curves
    ax = fig.add_axes([0.08, 0.42, 0.88, 0.46])

    ane_xs, ane_ys = zip(*ane_exp)
    ax.plot(list(ane_xs), list(ane_ys), "o-", color=c["ane"], linewidth=2.5,
            markersize=5, zorder=3, label="ANE (Neural Engine)")
    ane_best_i = list(ane_ys).index(min(ane_ys))
    ax.annotate(f"{ane_ys[ane_best_i]:.3f}",
                xy=(ane_xs[ane_best_i], ane_ys[ane_best_i]),
                xytext=(-50, -18), textcoords="offset points",
                fontsize=11, fontweight="bold", color=c["ane"], fontfamily=FONT,
                arrowprops=dict(arrowstyle="->", color=c["ane"], lw=1.5))

    mlx_xs, mlx_ys = zip(*mlx_exp)
    ax.plot(list(mlx_xs), list(mlx_ys), "o-", color=c["mlx"], linewidth=2.5,
            markersize=5, zorder=3, label="MLX (GPU)")
    mlx_best_i = list(mlx_ys).index(min(mlx_ys))
    ax.annotate(f"{mlx_ys[mlx_best_i]:.3f}",
                xy=(mlx_xs[mlx_best_i], mlx_ys[mlx_best_i]),
                xytext=(12, 10), textcoords="offset points",
                fontsize=11, fontweight="bold", color=c["mlx"], fontfamily=FONT,
                arrowprops=dict(arrowstyle="->", color=c["mlx"], lw=1.5))

    # Reference lines
    add_ref_lines(ax, c["ane"], 1.5949, "@danpacary: 1.595 (M4 Max)")
    ax.axhline(y=1.2661, color=c["mlx"], linewidth=1.5, linestyle=":", alpha=0.7)
    xlim = ax.get_xlim()
    ax.text(xlim[0] + (xlim[1] - xlim[0]) * 0.5, 1.2661 - 0.07,
            "@danpacary: 1.266 (M4 Max)", fontsize=7, color=c["mlx"], fontfamily=FONT, alpha=0.8)

    ax.set_xlabel("experiment", fontsize=8, color=c["dim"], fontfamily=FONT)
    ax.set_ylabel("val_bpb", fontsize=8, color=c["dim"], fontfamily=FONT)
    y_top = max(max(ane_ys), max(mlx_ys)) + 0.15
    ax.set_ylim(0.7, y_top)
    ax.legend(loc="upper right", fontsize=9, facecolor=c["card"],
             edgecolor=c["dimmer"], labelcolor=c["white"], prop={"family": FONT})
    style_ax(ax)

    # Cards
    ane_best = f"{min(ane_ys):.3f}"
    mlx_best = f"{min(mlx_ys):.3f}"
    draw_card(fig, 0.07, 0.12, 0.42, 0.24,
             c["ane"], "NEURAL ENGINE", ane_best,
             f"native Obj-C  |  {len(ane_exp)} experiments  |  5 min each",
             "1.595", "M4 Max 128GB")
    draw_card(fig, 0.56, 0.12, 0.42, 0.24,
             c["mlx"], "MLX GPU", mlx_best,
             f"MLX bf16  |  {len(mlx_exp)} experiments  |  5 min each",
             "1.266", "M4 Max 128GB")

    fig.text(0.5, 0.05,
             "zero interference — ANE + GPU run simultaneously  |  "
             "github.com/ncdrone/train-my-mac  |  made by @danpacary",
             fontsize=7.5, color=c["dimmer"], ha="center", fontfamily=FONT)

    return save_and_share(fig, "train-my-mac-gossip")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    chip, mem_gb = get_hardware_info()
    chip_display = chip.replace("Apple ", "")

    generated = []

    p = generate_experiments(chip_display, str(mem_gb))
    if p:
        generated.append(p)

    p = generate_overnight(chip_display, str(mem_gb))
    if p:
        generated.append(p)

    p = generate_gossip(chip_display, str(mem_gb))
    if p:
        generated.append(p)

    if not generated:
        print("No results found. Run sweep.sh, overnight.sh, or gossip.sh first.")


if __name__ == "__main__":
    main()
