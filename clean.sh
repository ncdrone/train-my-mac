#!/bin/bash
# clean.sh — Remove all generated artifacts from train-my-mac
# Usage: bash clean.sh          # interactive (confirms before deleting)
#        bash clean.sh --yes    # delete everything without prompting
#        bash clean.sh --all    # also delete cached data (~1GB in ~/.cache/autoresearch)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$HOME/.cache/autoresearch"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

AUTO_YES=false
CLEAN_CACHE=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_YES=true ;;
        --all)    CLEAN_CACHE=true; AUTO_YES=true ;;
    esac
done

echo ""
echo -e "${BOLD}  train-my-mac — cleanup${NC}"
echo ""

# Show what exists
TOTAL=0

if [ -d "$SCRIPT_DIR/engines" ]; then
    SIZE=$(du -sh "$SCRIPT_DIR/engines" 2>/dev/null | awk '{print $1}')
    echo -e "  engines/          ${DIM}$SIZE (cloned repos + venvs + builds)${NC}"
    TOTAL=1
fi

if [ -f "$SCRIPT_DIR/my_config.txt" ]; then
    echo -e "  my_config.txt     ${DIM}generated config${NC}"
    TOTAL=1
fi

if ls "$SCRIPT_DIR/results"/smoke_*.log "$SCRIPT_DIR/results"/sweep_*.log \
      "$SCRIPT_DIR/results"/overnight_*.log "$SCRIPT_DIR/results"/gossip_*.log \
      "$SCRIPT_DIR/results"/*_summary.txt 2>/dev/null | head -1 > /dev/null 2>&1; then
    echo -e "  results/*.log     ${DIM}run logs and summaries${NC}"
    TOTAL=1
fi

if [ -d "$CACHE_DIR" ]; then
    SIZE=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}')
    if [ "$CLEAN_CACHE" = true ]; then
        echo -e "  ~/.cache/autoresearch/  ${DIM}$SIZE (dataset + tokenizer) ${RED}[--all]${NC}"
    else
        echo -e "  ~/.cache/autoresearch/  ${DIM}$SIZE (dataset + tokenizer) ${YELLOW}kept unless --all${NC}"
    fi
fi

if [ "$TOTAL" -eq 0 ] && [ "$CLEAN_CACHE" = false ]; then
    echo -e "  ${GREEN}Nothing to clean.${NC}"
    echo ""
    exit 0
fi

echo ""

if [ "$AUTO_YES" = false ]; then
    echo "  This will delete engines/, my_config.txt, and run logs."
    echo "  Cached data (~1GB) is kept. Use --all to delete that too."
    echo ""
    read -p "  Delete? [y/N]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "  Cancelled."
        exit 0
    fi
fi

# Delete engines (repos, venvs, builds)
if [ -d "$SCRIPT_DIR/engines" ]; then
    rm -rf "$SCRIPT_DIR/engines"
    echo -e "  ${GREEN}Removed engines/${NC}"
fi

# Delete config
rm -f "$SCRIPT_DIR/my_config.txt"
echo -e "  ${GREEN}Removed my_config.txt${NC}"

# Delete run logs (keep sample results like PNGs)
rm -f "$SCRIPT_DIR/results"/smoke_*.log
rm -f "$SCRIPT_DIR/results"/sweep_*.log "$SCRIPT_DIR/results"/sweep_*_summary.txt
rm -f "$SCRIPT_DIR/results"/overnight_*.log "$SCRIPT_DIR/results"/overnight_*_summary.txt
rm -f "$SCRIPT_DIR/results"/gossip_*.log
echo -e "  ${GREEN}Removed run logs${NC}"

# Optionally delete cached data
if [ "$CLEAN_CACHE" = true ] && [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo -e "  ${GREEN}Removed ~/.cache/autoresearch/${NC}"
fi

echo ""
echo -e "  ${GREEN}Clean. Run ${BOLD}bash setup.sh${GREEN} to start fresh.${NC}"
echo ""
