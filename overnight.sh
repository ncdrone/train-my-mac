#!/bin/bash
# overnight.sh — Phase 2: Full training run
# Usage: bash overnight.sh [ane|mlx] [--lr X] [--accum N] [--steps N]
# Auto-launches in tmux so closing your terminal won't kill the run.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-wrap in tmux if not already inside one
if [ -z "$TMUX" ] && command -v tmux &>/dev/null; then
    SESSION="train-my-mac"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    echo "Launching in tmux session '$SESSION'..."
    echo "  Reattach anytime: tmux attach -t $SESSION"
    echo ""
    tmux new-session -d -s "$SESSION" "bash $0 $*; echo ''; echo 'Done. Press Enter to close.'; read"
    tmux attach -t "$SESSION"
    exit 0
fi
CONFIG_FILE="$SCRIPT_DIR/my_config.txt"
RESULTS_DIR="$SCRIPT_DIR/results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[0;90m'
NC='\033[0m'

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Run setup.sh first.${NC}"
    exit 1
fi

source "$CONFIG_FILE"
mkdir -p "$RESULTS_DIR"

# Engine selection (first positional arg)
ENGINE="ane"
OVERRIDE_LR=""
OVERRIDE_ACCUM=""
OVERRIDE_STEPS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        ane|mlx) ENGINE="$1"; shift ;;
        --lr) OVERRIDE_LR="$2"; shift 2 ;;
        --accum) OVERRIDE_ACCUM="$2"; shift 2 ;;
        --steps) OVERRIDE_STEPS="$2"; shift 2 ;;
        *) echo "Usage: bash overnight.sh [ane|mlx] [--lr X] [--accum N] [--steps N]"; exit 1 ;;
    esac
done

# ─── ANE OVERNIGHT ───────────────────────────────────────────────────────────

if [ "$ENGINE" = "ane" ]; then
    STEPS="${OVERRIDE_STEPS:-72000}"
    LR="${OVERRIDE_LR:-${ANE_LR:-2.5e-4}}"
    ACCUM="${OVERRIDE_ACCUM:-${ANE_ACCUM:-2}}"
    LOG_FILE="$RESULTS_DIR/overnight_ane.log"
    START_DATE=$(date +"%Y-%m-%d %H:%M")

    echo ""
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN}  ANE OVERNIGHT — $STEPS steps${NC}"
    echo -e "${CYAN}=========================================================${NC}"
    echo ""
    echo -e "  Chip:    $CHIP ($MEM_GB GB)"
    echo -e "  Preset:  $ANE_PRESET"
    echo -e "  LR:      $LR"
    echo -e "  Accum:   $ACCUM"
    echo -e "  Steps:   $STEPS"
    echo -e "  Recipe:  v3b (zero-init, softcap=15, split LR)"
    echo -e "  Log:     $LOG_FILE"
    echo -e "  Started: $START_DATE"
    echo ""
    echo -e "  ${DIM}What to watch:${NC}"
    echo -e "  ${DIM}  x[...] = activation magnitude. Should stay under 5.${NC}"
    echo -e "  ${DIM}  If x > 50, it's about to explode. Kill and lower LR.${NC}"
    echo -e "  ${DIM}  val_bpb should decrease steadily.${NC}"
    echo ""
    read -p "  Press Enter to start (Ctrl+C to cancel): "
    echo ""

    # v3b recipe — all params explicit
    "$ANE_BINARY" \
        --scratch \
        --steps "$STEPS" \
        --lr "$LR" \
        --accum "$ACCUM" \
        --warmup 720 \
        --clip 1.0 \
        --beta2 0.99 \
        --min-lr-frac 0.0 \
        --embed-lr-scale 5.0 \
        --matrix-lr-scale 0.05 \
        --data "$ANE_DATA/train_karpathy.bin" \
        --val "$ANE_DATA/val_karpathy.bin" \
        --token-bytes "$ANE_DATA/token_bytes.bin" \
        --val-interval 2000 \
        --val-steps 20 \
        2>&1 | tee "$LOG_FILE"

    EXIT_CODE=${PIPESTATUS[0]}
    END_DATE=$(date +"%Y-%m-%d %H:%M")

    echo ""

    if [ $EXIT_CODE -ne 0 ]; then
        echo -e "${RED}  RUN FAILED (exit code $EXIT_CODE)${NC}"
        echo "  Check: $LOG_FILE"
        echo "  Try: lower LR, increase warmup, or switch to Light preset"
        exit 1
    fi

    FINAL_BPB=$(grep "val_bpb" "$LOG_FILE" | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    TOTAL_STEPS=$(grep "^step" "$LOG_FILE" | tail -1 | grep -oE 'step [0-9]+' | grep -oE '[0-9]+')

    START_EPOCH=$(date -j -f "%Y-%m-%d %H:%M" "$START_DATE" "+%s" 2>/dev/null || echo 0)
    END_EPOCH=$(date +%s)
    WALL_HOURS=$(echo "scale=1; ($END_EPOCH - $START_EPOCH) / 3600" | bc)

    echo -e "${GREEN}=========================================================${NC}"
    echo -e "${GREEN}  ANE OVERNIGHT COMPLETE${NC}"
    echo -e "${GREEN}=========================================================${NC}"
    echo ""
    echo -e "  Final val_bpb: ${BOLD}$FINAL_BPB${NC}"
    echo -e "  Steps:         $TOTAL_STEPS"
    echo -e "  Wall time:     ${WALL_HOURS} hours"
    echo -e "  Config:        LR=$LR, accum=$ACCUM"
    echo ""
    echo -e "  ${DIM}Our best (M4 Max 128GB): val_bpb = 1.595${NC}"

    cat > "$RESULTS_DIR/overnight_ane_summary.txt" << EOF
engine=ane
chip=$CHIP
memory_gb=$MEM_GB
macos=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
preset=$ANE_PRESET
lr=$LR
accum=$ACCUM
steps=$TOTAL_STEPS
val_bpb=$FINAL_BPB
wall_hours=$WALL_HOURS
date=$END_DATE
EOF

fi

# ─── MLX OVERNIGHT ───────────────────────────────────────────────────────────

if [ "$ENGINE" = "mlx" ]; then
    LOG_FILE="$RESULTS_DIR/overnight_mlx.log"
    START_DATE=$(date +"%Y-%m-%d %H:%M")

    echo ""
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN}  MLX OVERNIGHT — Extended Run${NC}"
    echo -e "${CYAN}=========================================================${NC}"
    echo ""
    echo -e "  Chip:      $CHIP ($MEM_GB GB)"
    echo -e "  Engine:    MLX (bf16, Muon + AdamW)"
    echo -e "  Config:    Pre-optimized from 259 experiments"
    echo -e "  Budget:    5 hours (set TIME_BUDGET in prepare.py)"
    echo -e "  Log:       $LOG_FILE"
    echo -e "  Started:   $START_DATE"
    echo ""
    echo -e "  ${DIM}MLX uses a time budget, not step count.${NC}"
    echo -e "  ${DIM}Default is 5 minutes. For overnight, edit prepare.py:${NC}"
    echo ""
    echo -e "  ${YELLOW}  cd engines/autoresearch-mlx${NC}"
    echo -e "  ${YELLOW}  # Change TIME_BUDGET = 300 to TIME_BUDGET = 18000 (5 hours)${NC}"
    echo ""
    read -p "  Have you set TIME_BUDGET? Press Enter to start (Ctrl+C to cancel): "
    echo ""

    cd "$MLX_DIR"

    if command -v uv &>/dev/null; then
        uv run train.py 2>&1 | tee "$LOG_FILE"
    else
        python3 train.py 2>&1 | tee "$LOG_FILE"
    fi

    EXIT_CODE=${PIPESTATUS[0]}
    cd "$SCRIPT_DIR"
    END_DATE=$(date +"%Y-%m-%d %H:%M")

    MLX_BPB=$(grep "val_bpb:" "$LOG_FILE" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    MLX_STEPS=$(grep "num_steps:" "$LOG_FILE" 2>/dev/null | grep -oE '[0-9]+' | head -1)

    START_EPOCH=$(date -j -f "%Y-%m-%d %H:%M" "$START_DATE" "+%s" 2>/dev/null || echo 0)
    END_EPOCH=$(date +%s)
    WALL_HOURS=$(echo "scale=1; ($END_EPOCH - $START_EPOCH) / 3600" | bc)

    echo ""
    echo -e "${GREEN}=========================================================${NC}"
    echo -e "${GREEN}  MLX OVERNIGHT COMPLETE${NC}"
    echo -e "${GREEN}=========================================================${NC}"
    echo ""
    echo -e "  Final val_bpb: ${BOLD}${MLX_BPB:-N/A}${NC}"
    echo -e "  Steps:         ${MLX_STEPS:-N/A}"
    echo -e "  Wall time:     ${WALL_HOURS} hours"
    echo ""
    echo -e "  ${DIM}Our best (M4 Max 128GB, 259 experiments): val_bpb = 1.266${NC}"

    cat > "$RESULTS_DIR/overnight_mlx_summary.txt" << EOF
engine=mlx
chip=$CHIP
memory_gb=$MEM_GB
macos=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
val_bpb=${MLX_BPB:-N/A}
steps=${MLX_STEPS:-N/A}
wall_hours=$WALL_HOURS
date=$END_DATE
EOF

fi

# ─── Generate visualization ──────────────────────────────────────────────────

echo ""
echo -e "  ${CYAN}Generating results graphic...${NC}"
if python3 "$SCRIPT_DIR/visualize.py" 2>/dev/null; then
    echo -e "  ${GREEN}Saved to results/ and ~/Desktop/${NC}"
else
    echo -e "  ${YELLOW}Visualization failed. Run manually: python3 visualize.py${NC}"
fi

echo ""
echo -e "  ${DIM}Want to submit to the community leaderboard? (coming soon)${NC}"
echo ""
echo -e "${GREEN}=========================================================${NC}"
echo ""
