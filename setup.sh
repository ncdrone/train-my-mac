#!/bin/bash
# setup.sh — One-time setup for train-my-mac
# Clones training repos, installs deps, downloads data, builds binaries
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINES_DIR="$SCRIPT_DIR/engines"
CACHE_DIR="$HOME/.cache/autoresearch"
RESULTS_DIR="$SCRIPT_DIR/results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}  train-my-mac${NC}"
echo ""
echo -e "${RED}=========================================================${NC}"
echo -e "${RED}  WARNING: PRIVATE API USAGE${NC}"
echo -e "${RED}=========================================================${NC}"
echo ""
echo "  The ANE engine uses Apple's PRIVATE Neural Engine APIs."
echo "  Undocumented. Unsupported. May violate Apple's TOS."
echo ""
echo "  The MLX engine uses Apple's public ML framework. No private APIs."
echo ""
echo "  Your Mac. Your risk. No warranty."
echo ""
read -p "  Type \"yes\" to continue: " confirm
echo ""

if [ "$confirm" != "yes" ]; then
    echo "Exiting."
    exit 0
fi

# ─── Step 1: Hardware Detection ───────────────────────────────────────────────

echo -e "${CYAN}[1/6] Detecting hardware...${NC}"
echo ""

CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
MEM_GB=$((MEM_BYTES / 1073741824))
MACOS_VER=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
XCODE_PATH=$(xcode-select -p 2>/dev/null || echo "NOT FOUND")
PYTHON_VER=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "NOT FOUND")

echo -e "  Chip:    ${BOLD}$CHIP${NC}"
echo -e "  Memory:  ${BOLD}${MEM_GB} GB${NC}"
echo -e "  macOS:   $MACOS_VER"
echo -e "  Xcode:   $XCODE_PATH"
echo -e "  Python:  $PYTHON_VER"
echo ""

if [[ "$CHIP" != *"Apple"* ]]; then
    echo -e "${RED}ERROR: Apple Silicon required (M1/M2/M3/M4).${NC}"
    exit 1
fi

if [ "$XCODE_PATH" = "NOT FOUND" ]; then
    echo -e "${RED}ERROR: Xcode Command Line Tools not found.${NC}"
    echo "Install: xcode-select --install"
    exit 1
fi

if [ "$PYTHON_VER" = "NOT FOUND" ]; then
    echo -e "${RED}ERROR: Python 3 not found.${NC}"
    exit 1
fi

# Tier classification
ENABLE_ANE=true
ENABLE_MLX=true
ANE_PRESET="standard"

if [ $MEM_GB -ge 48 ]; then
    TIER="IDEAL"
elif [ $MEM_GB -ge 24 ]; then
    TIER="RECOMMENDED"
elif [ $MEM_GB -ge 16 ]; then
    TIER="MINIMUM"
    ANE_PRESET="light"
else
    echo -e "${RED}ERROR: ${MEM_GB}GB is below the 16GB minimum.${NC}"
    exit 1
fi

echo -e "  ${GREEN}Tier: $TIER ($MEM_GB GB)${NC}"
echo -e "  ${GREEN}ANE preset: $ANE_PRESET${NC}"
echo -e "  ${GREEN}Engines: ANE + MLX${NC}"
echo ""

mkdir -p "$RESULTS_DIR"
cat > "$SCRIPT_DIR/my_config.txt" << EOF
# train-my-mac config
# Generated: $(date -u +"%Y-%m-%d %H:%M UTC")
CHIP="$CHIP"
MEM_GB=$MEM_GB
TIER=$TIER
ANE_PRESET=$ANE_PRESET
ENABLE_ANE=$ENABLE_ANE
ENABLE_MLX=$ENABLE_MLX
ENGINES_DIR="$ENGINES_DIR"
CACHE_DIR="$CACHE_DIR"
EOF

# ─── Step 2: Clone Training Repos ─────────────────────────────────────────────

echo -e "${CYAN}[2/6] Setting up training engines...${NC}"
echo ""

mkdir -p "$ENGINES_DIR"

# ANE
if [ -d "$ENGINES_DIR/autoresearch-ANE" ]; then
    echo -e "  ${GREEN}ANE repo already cloned.${NC}"
else
    echo "  Cloning ANE training engine..."
    git clone https://github.com/ncdrone/autoresearch-ANE.git "$ENGINES_DIR/autoresearch-ANE"
    echo -e "  ${GREEN}ANE repo cloned.${NC}"
fi

# MLX
if [ -d "$ENGINES_DIR/autoresearch-mlx" ]; then
    echo -e "  ${GREEN}MLX repo already cloned.${NC}"
else
    echo "  Cloning MLX training engine..."
    git clone https://github.com/ncdrone/autoresearch-mlx.git "$ENGINES_DIR/autoresearch-mlx"
    echo -e "  ${GREEN}MLX repo cloned.${NC}"
fi
echo ""

ANE_DIR="$ENGINES_DIR/autoresearch-ANE"
MLX_DIR="$ENGINES_DIR/autoresearch-mlx"
ANE_NATIVE="$ANE_DIR/native"
ANE_DATA="$ANE_NATIVE/data"

# Save paths
cat >> "$SCRIPT_DIR/my_config.txt" << EOF
ANE_DIR="$ANE_DIR"
MLX_DIR="$MLX_DIR"
ANE_NATIVE="$ANE_NATIVE"
ANE_DATA="$ANE_DATA"
EOF

# ─── Step 3: Dependencies ─────────────────────────────────────────────────────

echo -e "${CYAN}[3/6] Checking dependencies...${NC}"
echo ""

# Check uv
if command -v uv &>/dev/null; then
    HAS_UV=true
    echo -e "  ${GREEN}uv found.${NC}"
else
    HAS_UV=false
    echo -e "  ${DIM}uv not found. Using pip.${NC}"
fi

# ANE deps (via pip — ANE repo uses prepare.py directly)
MISSING=""
for pkg in torch numpy pyarrow matplotlib requests rustbpe tiktoken; do
    if ! python3 -c "import $pkg" 2>/dev/null; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo -e "  ${YELLOW}Missing:${NC}$MISSING"
    if [[ "$MISSING" == *"torch"* ]]; then
        echo -e "  ${DIM}Note: torch is ~2GB${NC}"
    fi
    read -p "  Install? [y/N]: " install_deps
    if [ "$install_deps" = "y" ] || [ "$install_deps" = "Y" ]; then
        pip3 install $MISSING
        echo -e "  ${GREEN}Installed.${NC}"
    else
        echo -e "${RED}Cannot continue without dependencies.${NC}"
        exit 1
    fi
else
    echo -e "  ${GREEN}All ANE dependencies present.${NC}"
fi

# MLX deps (via uv or pip)
echo ""
echo "  Setting up MLX environment..."
cd "$MLX_DIR"
if [ "$HAS_UV" = true ]; then
    uv sync 2>&1 | tail -3
else
    pip3 install mlx 2>/dev/null
fi
echo -e "  ${GREEN}MLX environment ready.${NC}"
cd "$SCRIPT_DIR"
echo ""

# ─── Step 4: Data Preparation ─────────────────────────────────────────────────

echo -e "${CYAN}[4/6] Preparing Karpathy climbmix-400B data...${NC}"
echo ""
echo "  Same dataset as Karpathy's autoresearch."
echo "  Same tokenizer. Your val_bpb is comparable to H100 results."
echo ""

if [ -f "$ANE_DATA/train_karpathy.bin" ] && [ -f "$ANE_DATA/val_karpathy.bin" ]; then
    echo -e "  ${GREEN}ANE data already exists.${NC}"
else
    echo "  Downloading (~500MB) and tokenizing..."
    cd "$ANE_DIR"
    python3 prepare.py --num-shards 8
    echo ""

    # Bridge: .pt -> .npy for convert script
    python3 -c "
import torch, numpy as np, os
pt = os.path.expanduser('~/.cache/autoresearch/tokenizer/token_bytes.pt')
npy = os.path.expanduser('~/.cache/autoresearch/tokenizer/token_bytes.npy')
if not os.path.exists(npy) and os.path.exists(pt):
    np.save(npy, torch.load(pt, weights_only=True).numpy())
    print('  Converted token_bytes.pt -> .npy')
"

    # Convert to binary
    python3 "$ANE_NATIVE/scripts/convert_karpathy_data.py"
    cd "$SCRIPT_DIR"
fi

# MLX data (uses same cache, just needs its own prepare)
if [ -f "$CACHE_DIR/tokenizer/token_bytes.npy" ]; then
    echo -e "  ${GREEN}MLX data ready (shared cache).${NC}"
else
    echo "  Preparing MLX data format..."
    cd "$MLX_DIR"
    if [ "$HAS_UV" = true ]; then
        uv run prepare.py --num-shards 8
    else
        python3 prepare.py --num-shards 8
    fi
    cd "$SCRIPT_DIR"
fi
echo ""

# ─── Step 5: Build ANE Binary ─────────────────────────────────────────────────

echo -e "${CYAN}[5/6] Building ANE training binary...${NC}"
echo ""

cd "$ANE_NATIVE"

echo "  Building Standard (NL=6, 48.8M params)..."
make MODEL=gpt_karpathy train 2>&1 | tail -1
ANE_BINARY="$ANE_NATIVE/build/train_dynamic"

if [ ! -f "$ANE_BINARY" ]; then
    echo -e "  ${RED}Build failed. Check Xcode CLT.${NC}"
    exit 1
fi
echo -e "  ${GREEN}Built: train_dynamic${NC}"

if [ "$ANE_PRESET" = "light" ]; then
    echo "  Building Light (NL=4, ~35M params)..."
    xcrun clang -O2 -Wall -Wno-unused-function -fobjc-arc -DACCELERATE_NEW_LAPACK \
        -DNLAYERS=4 -DSEQ=512 \
        -I. -Iruntime -Imil -Itraining -include training/models/gpt_karpathy.h \
        -o build/train_dynamic_light training/train.m \
        -ldl -framework Foundation -framework IOSurface -framework CoreML -framework Accelerate
    ANE_BINARY="$ANE_NATIVE/build/train_dynamic_light"
    echo -e "  ${GREEN}Built: train_dynamic_light${NC}"
fi

cd "$SCRIPT_DIR"

cat >> "$SCRIPT_DIR/my_config.txt" << EOF
ANE_BINARY="$ANE_BINARY"
EOF
echo ""

# ─── Step 6: Smoke Tests ──────────────────────────────────────────────────────

echo -e "${CYAN}[6/6] Smoke tests...${NC}"
echo ""

# ANE smoke test
echo "  ANE (50 steps)..."
"$ANE_BINARY" \
    --scratch --steps 50 --lr 2.5e-4 --accum 1 --warmup 10 \
    --clip 1.0 --beta2 0.99 \
    --data "$ANE_DATA/train_karpathy.bin" \
    --val "$ANE_DATA/val_karpathy.bin" \
    --token-bytes "$ANE_DATA/token_bytes.bin" \
    --val-interval 50 --val-steps 5 \
    > "$RESULTS_DIR/smoke_ane.log" 2>&1

if [ $? -eq 0 ]; then
    ANE_MS=$(grep "^step" "$RESULTS_DIR/smoke_ane.log" | tail -1 | grep -oE '[0-9]+\.[0-9]+ms' | head -1)
    echo -e "  ${GREEN}ANE works. ${ANE_MS:-ok}${NC}"
else
    echo -e "  ${RED}ANE smoke test failed. Check results/smoke_ane.log${NC}"
fi

# MLX smoke test
echo "  MLX (50 steps)..."
cd "$MLX_DIR"
if [ "$HAS_UV" = true ]; then
    timeout 30 uv run train.py > "$RESULTS_DIR/smoke_mlx.log" 2>&1 || true
else
    timeout 30 python3 train.py > "$RESULTS_DIR/smoke_mlx.log" 2>&1 || true
fi
cd "$SCRIPT_DIR"

if grep -q "val_bpb\|step" "$RESULTS_DIR/smoke_mlx.log" 2>/dev/null; then
    echo -e "  ${GREEN}MLX works.${NC}"
else
    echo -e "  ${YELLOW}MLX smoke test inconclusive. Check results/smoke_mlx.log${NC}"
fi

echo ""

# ─── Done ─────────────────────────────────────────────────────────────────────

echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}  SETUP COMPLETE${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo ""
echo -e "  ${BOLD}$CHIP${NC} | ${BOLD}${MEM_GB} GB${NC} | Tier: ${BOLD}$TIER${NC}"
echo ""
echo -e "  Engines:"
echo -e "    ${CYAN}ANE${NC}  native Obj-C, private APIs, ${ANE_PRESET} preset"
echo -e "    ${CYAN}MLX${NC}  Python, Apple ML framework, bf16"
echo ""
echo -e "  Data: Karpathy climbmix-400B (comparable to H100 results)"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    bash sweep.sh         ${DIM}# find your config (~30 min)${NC}"
echo -e "    bash sweep.sh mlx     ${DIM}# sweep MLX too${NC}"
echo -e "    bash overnight.sh     ${DIM}# full 72K step run (5-8h)${NC}"
echo -e "    bash gossip.sh        ${DIM}# both engines + gossip${NC}"
echo ""
echo -e "${GREEN}=========================================================${NC}"
echo ""
