#!/bin/bash
# gossip.sh — Run both ANE + MLX engines with shared gossip
# The engines write results to a shared JSONL file.
# Cross-pollination: discoveries from one inform the other.
# Auto-launches in tmux so closing your terminal won't kill the run.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-wrap in tmux if not already inside one
if [ -z "$TMUX" ] && command -v tmux &>/dev/null; then
    SESSION="train-gossip"
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
GOSSIP_DIR="$HOME/.cache/autoresearch/gossip"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[0;90m'
PINK='\033[38;5;213m'
NC='\033[0m'

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Run setup.sh first.${NC}"
    exit 1
fi

source "$CONFIG_FILE"
mkdir -p "$RESULTS_DIR" "$GOSSIP_DIR"

GOSSIP_FILE="$GOSSIP_DIR/shared_experiments.jsonl"

echo ""
echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  GOSSIP MODE — Both Engines, Shared Intelligence${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""
echo -e "  ${CYAN}ANE${NC}  native Obj-C, private APIs, ${ANE_PRESET} preset"
echo -e "  ${PINK}MLX${NC}  Python, Apple ML framework, bf16"
echo ""
echo -e "  Gossip file: $GOSSIP_FILE"
echo ""
echo -e "  ${DIM}Both engines run simultaneously on your chip.${NC}"
echo -e "  ${DIM}ANE uses the Neural Engine. MLX uses the GPU.${NC}"
echo -e "  ${DIM}Zero interference — they don't compete for resources.${NC}"
echo ""
echo -e "  ${DIM}Each engine writes results to the shared gossip file.${NC}"
echo -e "  ${DIM}Cross-pollination compounds discoveries over time.${NC}"
echo ""

# Use sweep config or defaults
LR="${ANE_LR:-2.5e-4}"
ACCUM="${ANE_ACCUM:-2}"
ANE_STEPS="${1:-72000}"

echo -e "  ANE: LR=$LR, accum=$ACCUM, $ANE_STEPS steps"
echo -e "  MLX: pre-optimized defaults"
echo ""
read -p "  Press Enter to start both engines (Ctrl+C to cancel): "
echo ""

ANE_LOG="$RESULTS_DIR/gossip_ane.log"
MLX_LOG="$RESULTS_DIR/gossip_mlx.log"

# Cleanup on Ctrl+C
cleanup() {
    echo ""
    echo "  Stopping engines..."
    kill $ANE_PID $MLX_PID 2>/dev/null
    wait $ANE_PID $MLX_PID 2>/dev/null
    echo "  Stopped."
    exit 0
}
trap cleanup INT TERM

# ─── Launch ANE in background ────────────────────────────────────────────────

echo -e "  ${CYAN}Starting ANE...${NC}"

"$ANE_BINARY" \
    --scratch \
    --steps "$ANE_STEPS" \
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
    > "$ANE_LOG" 2>&1 &

ANE_PID=$!
echo -e "  ${CYAN}ANE PID: $ANE_PID${NC}"

# ─── Launch MLX in background ────────────────────────────────────────────────

echo -e "  ${PINK}Starting MLX...${NC}"

cd "$MLX_DIR"
if command -v uv &>/dev/null; then
    uv run train.py > "$MLX_LOG" 2>&1 &
else
    python3 train.py > "$MLX_LOG" 2>&1 &
fi
MLX_PID=$!
cd "$SCRIPT_DIR"

echo -e "  ${PINK}MLX PID: $MLX_PID${NC}"
echo ""

# ─── Monitor ─────────────────────────────────────────────────────────────────

echo -e "${BOLD}  Both engines running. Monitoring...${NC}"
echo -e "  ${DIM}Ctrl+C to stop both. Logs: results/gossip_*.log${NC}"
echo ""

# Wait for both, reporting status every 60s
while true; do
    ANE_ALIVE=false
    MLX_ALIVE=false

    if kill -0 "$ANE_PID" 2>/dev/null; then ANE_ALIVE=true; fi
    if kill -0 "$MLX_PID" 2>/dev/null; then MLX_ALIVE=true; fi

    # Both done?
    if [ "$ANE_ALIVE" = false ] && [ "$MLX_ALIVE" = false ]; then
        break
    fi

    # Status update
    NOW=$(date +"%H:%M:%S")
    ANE_STATUS="done"
    MLX_STATUS="done"
    [ "$ANE_ALIVE" = true ] && ANE_STATUS="running"
    [ "$MLX_ALIVE" = true ] && MLX_STATUS="running"

    # Latest val_bpb from each
    ANE_LATEST=$(grep "val_bpb" "$ANE_LOG" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    MLX_LATEST=$(grep "val_bpb" "$MLX_LOG" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)

    echo -e "  [$NOW] ANE: $ANE_STATUS ${ANE_LATEST:+(bpb=$ANE_LATEST)}  |  MLX: $MLX_STATUS ${MLX_LATEST:+(bpb=$MLX_LATEST)}"

    sleep 60
done

# ─── Results ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}  GOSSIP RUN COMPLETE${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo ""

ANE_FINAL=$(grep "val_bpb" "$ANE_LOG" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
MLX_FINAL=$(grep "val_bpb:" "$MLX_LOG" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)

echo -e "  ${CYAN}ANE${NC} final val_bpb: ${BOLD}${ANE_FINAL:-N/A}${NC}"
echo -e "  ${PINK}MLX${NC} final val_bpb: ${BOLD}${MLX_FINAL:-N/A}${NC}"
echo ""
echo -e "  ${DIM}Our bests (M4 Max 128GB):${NC}"
echo -e "  ${DIM}  ANE: 1.595  |  MLX: 1.266${NC}"
echo ""
echo -e "  Gossip file: $GOSSIP_FILE"
echo -e "  Logs: results/gossip_ane.log, results/gossip_mlx.log"
echo ""
echo -e "${GREEN}=========================================================${NC}"
echo ""
