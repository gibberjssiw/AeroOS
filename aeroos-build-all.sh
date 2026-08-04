#!/bin/bash
###############################################################################
# AeroOS - Master Build Orchestrator
#
# This script runs the entire AeroOS ISO build pipeline in sequence:
#   Step 1: Chroot customization (GNOME, extensions, dconf, branding, autostart)
#   Step 2: Plymouth boot animation (Windows 7 glowing orb)
#   Step 3: ISO compilation & packaging (live-build → bootable .ISO)
#
# Usage:
#   sudo ./aeroos-build-all.sh
#
# Output:
#   aeroos-build/AeroOS-1.0-amd64.iso
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         AeroOS — Master Build Pipeline       ║${NC}"
echo -e "${BOLD}║         Aero Glass Edition v1.0              ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run as root (use sudo).${NC}"
    exit 1
fi

REQUIRED_SCRIPTS=(
    "aeroos-step1-chroot.sh"
    "aeroos-step2-plymouth.sh"
    "aeroos-step3-iso-build.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
        echo -e "${RED}[ERROR] Missing required script: ${script}${NC}"
        exit 1
    fi
done

echo -e "${CYAN}[INFO]${NC} All scripts found. Starting build pipeline…"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Run Step 3 (which orchestrates Steps 1 & 2 as chroot hooks internally)
# ─────────────────────────────────────────────────────────────────────────────
# Step 3's live-build process calls Steps 1 & 2 automatically as chroot hooks.
# We run Step 3 which handles the full pipeline:
#   lb bootstrap → lb chroot (runs hook 00 = Step 1, hook 01 = Step 2) → lb binary

echo -e "${BOLD}── Launching ISO Build (Step 3 — includes Steps 1 & 2 as hooks) ──${NC}"
echo ""

bash "${SCRIPT_DIR}/aeroos-step3-iso-build.sh"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  AeroOS Build Pipeline — FINISHED            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
