#!/bin/bash
# sweep.sh — Phase 1: Diagnostic experiments to find your best config
# Usage: bash sweep.sh [ane|mlx|both]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

# Engine selection
ENGINE="${1:-ane}"

case "$ENGINE" in
    ane)   DO_ANE=true;  DO_MLX=false ;;
    mlx)   DO_ANE=false; DO_MLX=true  ;;
    both)  DO_ANE=true;  DO_MLX=true  ;;
    *)     echo "Usage: bash sweep.sh [ane|mlx|both]"; exit 1 ;;
esac

# ─── ANE SWEEP ───────────────────────────────────────────────────────────────

run_ane_experiment() {
    local EXP_NUM=$1
    local EXP_NAME=$2
    local LR=$3
    local ACCUM=$4
    local LOG_FILE="$RESULTS_DIR/sweep_ane_${EXP_NUM}.log"

    echo -e "  ${CYAN}Experiment $EXP_NUM/6: $EXP_NAME${NC}"
    echo -e "  ${DIM}LR=$LR, accum=$ACCUM${NC}"

    START_TIME=$(date +%s)

    "$ANE_BINARY" \
        --scratch \
        --steps 3000 \
        --lr "$LR" \
        --accum "$ACCUM" \
        --warmup 720 --clip 1.0 --beta2 0.99 \
        --min-lr-frac 0.0 --embed-lr-scale 5.0 --matrix-lr-scale 0.05 \
        --data "$ANE_DATA/train_karpathy.bin" \
        --val "$ANE_DATA/val_karpathy.bin" \
        --token-bytes "$ANE_DATA/token_bytes.bin" \
        --val-interval 1000 --val-steps 10 \
        > "$LOG_FILE" 2>&1

    EXIT_CODE=$?
    END_TIME=$(date +%s)
    WALL_SEC=$((END_TIME - START_TIME))

    if [ $EXIT_CODE -ne 0 ]; then
        VAL_BPB="FAILED"
        MS_STEP="--"
        STATUS="exploded"
    else
        VAL_BPB=$(grep "val_bpb" "$LOG_FILE" | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        [ -z "$VAL_BPB" ] && VAL_BPB="N/A"

        MS_STEP=$(grep "^step" "$LOG_FILE" | tail -1 | grep -oE '[0-9]+\.[0-9]+ms' | head -1)
        [ -z "$MS_STEP" ] && MS_STEP="--"

        MAX_ACT=$(grep "x\[" "$LOG_FILE" | grep -oE '[0-9]+\.[0-9]+' | sort -n | tail -1)
        if [ -n "$MAX_ACT" ] && (( $(echo "$MAX_ACT > 50" | bc -l 2>/dev/null || echo 0) )); then
            STATUS="exploded"
        else
            STATUS="ok"
        fi
    fi

    echo -e "  val_bpb=${BOLD}$VAL_BPB${NC}  ms/step=$MS_STEP  status=$STATUS  (${WALL_SEC}s)"
    echo ""

    echo "$EXP_NUM|$EXP_NAME|$LR|$ACCUM|$VAL_BPB|$MS_STEP|$STATUS" >> "$RESULTS_DIR/sweep_ane_summary.txt"
}

if [ "$DO_ANE" = true ]; then
    echo ""
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN}  ANE SWEEP — Find Your Best Config${NC}"
    echo -e "${CYAN}=========================================================${NC}"
    echo ""
    echo -e "  Binary:  $ANE_BINARY"
    echo -e "  Steps:   3000 per experiment (~5 min each)"
    echo -e "  Recipe:  v3b (zero-init, softcap=15, split LR)"
    echo -e "  Total:   ~30 minutes for 6 experiments"
    echo ""

    rm -f "$RESULTS_DIR/sweep_ane_summary.txt"

    echo -e "${BOLD}  --- LR SWEEP ---${NC}"
    echo ""

    run_ane_experiment 1 "LR=1e-4 (conservative)" "1e-4" 2
    run_ane_experiment 2 "LR=2.5e-4 (our best)" "2.5e-4" 2
    run_ane_experiment 3 "LR=5e-4 (aggressive)" "5e-4" 2
    run_ane_experiment 4 "LR=1e-3 (very aggressive)" "1e-3" 2

    # Find best LR
    BEST_LR_LINE=$(grep "|ok$" "$RESULTS_DIR/sweep_ane_summary.txt" | head -4 | sort -t'|' -k5 -n | head -1)
    BEST_LR=$(echo "$BEST_LR_LINE" | cut -d'|' -f3)
    BEST_LR_BPB=$(echo "$BEST_LR_LINE" | cut -d'|' -f5)

    # Fallback if all LRs exploded
    if [ -z "$BEST_LR" ]; then
        echo -e "  ${YELLOW}All LRs exploded! Falling back to conservative LR=1e-4${NC}"
        BEST_LR="1e-4"
        BEST_LR_BPB="N/A"
    fi

    echo -e "  ${GREEN}Best LR: $BEST_LR (val_bpb=$BEST_LR_BPB)${NC}"
    echo ""

    echo -e "${BOLD}  --- ACCUMULATION SWEEP (with LR=$BEST_LR) ---${NC}"
    echo ""

    run_ane_experiment 5 "accum=1 (LR=$BEST_LR)" "$BEST_LR" 1
    run_ane_experiment 6 "accum=2 (LR=$BEST_LR)" "$BEST_LR" 2

    BEST_ACCUM_LINE=$(grep "|ok$" "$RESULTS_DIR/sweep_ane_summary.txt" | tail -2 | sort -t'|' -k5 -n | head -1)
    BEST_ANE_ACCUM=$(echo "$BEST_ACCUM_LINE" | cut -d'|' -f4)
    BEST_ANE_BPB=$(echo "$BEST_ACCUM_LINE" | cut -d'|' -f5)

    # Fallback if accum sweep also exploded
    if [ -z "$BEST_ANE_ACCUM" ]; then
        BEST_ANE_ACCUM="2"
        BEST_ANE_BPB="${BEST_LR_BPB}"
    fi

    # Print ANE summary
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN}  ANE SWEEP RESULTS${NC}"
    echo -e "${CYAN}=========================================================${NC}"
    echo ""
    printf "  ${BOLD}%-4s %-28s %-8s %-10s %-10s %s${NC}\n" "#" "Experiment" "LR" "val_bpb" "ms/step" "Status"
    echo -e "  ${DIM}──── ──────────────────────────── ──────── ────────── ────────── ──────${NC}"

    while IFS='|' read -r num name lr accum bpb ms status; do
        if [ "$status" = "exploded" ]; then COLOR=$RED
        elif [ "$bpb" = "$BEST_ANE_BPB" ]; then COLOR=$GREEN
        else COLOR=$NC; fi
        printf "  ${COLOR}%-4s %-28s %-8s %-10s %-10s %s${NC}\n" "$num" "$name" "$lr" "$bpb" "$ms" "$status"
    done < "$RESULTS_DIR/sweep_ane_summary.txt"

    echo ""
    echo -e "  ${GREEN}ANE CONFIG: LR=$BEST_LR, accum=$BEST_ANE_ACCUM${NC}"
    echo ""

    # Save to config
    cat >> "$CONFIG_FILE" << EOF
ANE_LR=$BEST_LR
ANE_ACCUM=$BEST_ANE_ACCUM
EOF
fi

# ─── MLX SWEEP ───────────────────────────────────────────────────────────────

if [ "$DO_MLX" = true ]; then
    echo ""
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN}  MLX SWEEP — Baseline Run${NC}"
    echo -e "${CYAN}=========================================================${NC}"
    echo ""
    echo -e "  Engine:  MLX (Apple ML framework, bf16)"
    echo -e "  Config:  Pre-optimized (259 experiments went into these defaults)"
    echo -e "  Budget:  5 minutes"
    echo ""
    echo -e "  ${DIM}MLX train.py has pre-tuned hyperparameters from our research.${NC}"
    echo -e "  ${DIM}This baseline tells you how fast your Mac runs MLX.${NC}"
    echo ""

    MLX_LOG="$RESULTS_DIR/sweep_mlx.log"

    cd "$MLX_DIR"

    echo "  Running MLX baseline..."
    START_TIME=$(date +%s)

    uv run train.py > "$MLX_LOG" 2>&1 || true

    END_TIME=$(date +%s)
    WALL_SEC=$((END_TIME - START_TIME))
    cd "$SCRIPT_DIR"

    # Extract MLX result
    MLX_BPB=$(grep "val_bpb:" "$MLX_LOG" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    MLX_STEPS=$(grep "num_steps:" "$MLX_LOG" 2>/dev/null | grep -oE '[0-9]+' | head -1)

    if [ -n "$MLX_BPB" ]; then
        echo -e "  ${GREEN}val_bpb = ${BOLD}$MLX_BPB${NC}  (${MLX_STEPS} steps in ${WALL_SEC}s)"
        echo ""

        cat >> "$CONFIG_FILE" << EOF
MLX_BPB_5MIN=$MLX_BPB
MLX_STEPS_5MIN=$MLX_STEPS
EOF
    else
        echo -e "  ${YELLOW}MLX run inconclusive. Check results/sweep_mlx.log${NC}"
    fi

    echo -e "  ${DIM}Our best (M4 Max 128GB, 259 experiments): val_bpb = 1.266${NC}"
    echo ""
    echo -e "${CYAN}=========================================================${NC}"
    echo ""
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}  SWEEP COMPLETE${NC}"
echo ""
if [ "$DO_ANE" = true ]; then
    echo -e "  ANE: LR=$BEST_LR, accum=$BEST_ANE_ACCUM"
fi
if [ "$DO_MLX" = true ] && [ -n "$MLX_BPB" ]; then
    echo -e "  MLX: val_bpb=$MLX_BPB (5-min baseline)"
fi
echo ""
echo -e "  Saved to: my_config.txt"
echo -e "  Logs in:  results/"
echo ""
echo -e "  ${CYAN}Next:${NC}"
echo -e "    ${BOLD}bash overnight.sh${NC}         ${DIM}# ANE overnight${NC}"
echo -e "    ${BOLD}bash overnight.sh mlx${NC}     ${DIM}# MLX overnight${NC}"
echo -e "    ${BOLD}bash gossip.sh${NC}            ${DIM}# both engines + gossip${NC}"
echo ""
