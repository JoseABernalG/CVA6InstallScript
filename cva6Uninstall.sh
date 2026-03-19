#!/usr/bin/env bash
set -euo pipefail

# Enable tab completion for path inputs
bind 'set completion-ignore-case on' 2>/dev/null || true

# ============================================================
# CVA6 Uninstallation Script
# ============================================================
# This script removes CVA6 and its dependencies
# ============================================================

echo ""
echo "======================================"
echo "CVA6 Uninstallation"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to ask for confirmation
ask_yes_no() {
  local prompt="$1"
  local ans
  while true; do
    read -p "$prompt (y/n): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      return 0
    elif [[ "$ans" =~ ^[Nn]$ ]]; then
      return 1
    else
      echo "  Please answer 'y' (yes) or 'n' (no)."
    fi
  done
}

# ============================================================
# Get installation paths
# ============================================================
echo "Enter the paths used during installation:"
echo ""

# Try to detect paths from .bashrc if available
DETECTED_CVA6=""
DETECTED_RISCV=""
DETECTED_VERILATOR=""
DETECTED_SPIKE=""

if [[ -f "$HOME/.bashrc" ]]; then
  echo "Detecting paths from ~/.bashrc..."
  DETECTED_CVA6=$(grep -oP 'export CVA6_REPO_DIR="\K[^"]+' "$HOME/.bashrc" 2>/dev/null || true)
  DETECTED_RISCV=$(grep -oP 'export RISCV="\K[^"]+' "$HOME/.bashrc" 2>/dev/null || true)
  DETECTED_VERILATOR=$(grep -oP 'export VERILATOR_INSTALL_DIR="\K[^"]+' "$HOME/.bashrc" 2>/dev/null || true)
  DETECTED_SPIKE=$(grep -oP 'export SPIKE_INSTALL_DIR="\K[^"]+' "$HOME/.bashrc" 2>/dev/null || true)
  
  if [[ -n "$DETECTED_CVA6" ]] || [[ -n "$DETECTED_RISCV" ]]; then
    echo "  ✓ Found CVA6_REPO: ${DETECTED_CVA6:-not set}"
    echo "  ✓ Found RISCV: ${DETECTED_RISCV:-not set}"
    echo "  ✓ Found VERILATOR: ${DETECTED_VERILATOR:-not set}"
    echo "  ✓ Found SPIKE: ${DETECTED_SPIKE:-not set}"
    echo ""
  fi
fi

# Use detected paths as defaults, or ask user
if [ -t 0 ]; then
  read -e -p "Enter CVA6 repo path [${DETECTED_CVA6}]: " CVA6_REPO
  read -e -p "Enter RISCV install path [${DETECTED_RISCV}]: " RISCV
else
  read -p "Enter CVA6 repo path [${DETECTED_CVA6}]: " CVA6_REPO
  read -p "Enter RISCV install path [${DETECTED_RISCV}]: " RISCV
fi

# Use detected values as defaults if empty
CVA6_REPO="${CVA6_REPO:-$DETECTED_CVA6}"
RISCV="${RISCV:-$DETECTED_RISCV}"

# Use detected Verilator/Spike paths, or derive from CVA6_REPO
VERILATOR_PATH="${DETECTED_VERILATOR:-${CVA6_REPO}/tools/verilator-v5.008}"
SPIKE_PATH="${DETECTED_SPIKE:-${CVA6_REPO}/tools/spike}"

# Expand paths
[[ "$CVA6_REPO" == "~"* ]] && CVA6_REPO="${CVA6_REPO/#\~/$HOME}"
[[ "$RISCV" == "~"* ]] && RISCV="${RISCV/#\~/$HOME}"
[[ "$VERILATOR_PATH" == "~"* ]] && VERILATOR_PATH="${VERILATOR_PATH/#\~/$HOME}"
[[ "$SPIKE_PATH" == "~"* ]] && SPIKE_PATH="${SPIKE_PATH/#\~/$HOME}"

CVA6_REPO=$(realpath "$CVA6_REPO" 2>/dev/null || echo "$CVA6_REPO")
RISCV=$(realpath "$RISCV" 2>/dev/null || echo "$RISCV")
VERILATOR_PATH=$(realpath "$VERILATOR_PATH" 2>/dev/null || echo "$VERILATOR_PATH")
SPIKE_PATH=$(realpath "$SPIKE_PATH" 2>/dev/null || echo "$SPIKE_PATH")

echo ""
echo "Paths to remove:"
echo "  CVA6_REPO: $CVA6_REPO"
echo "  RISCV:     $RISCV"
echo ""

# ============================================================
# Validate paths
echo "Validating paths..."

CVA6_EXISTS="[${RED}✗${NC}]"
RISCV_EXISTS="[${RED}✗${NC}]"
SPIKE_EXISTS="[${RED}✗${NC}]"
VERILATOR_EXISTS="[${RED}✗${NC}]"

if [[ -d "$CVA6_REPO" ]]; then
  CVA6_EXISTS="[${GREEN}✓${NC}]"
fi

if [[ -d "$RISCV" ]]; then
  RISCV_EXISTS="[${GREEN}✓${NC}]"
fi

if [[ -d "$SPIKE_PATH" ]]; then
  SPIKE_EXISTS="[${GREEN}✓${NC}]"
fi

if [[ -d "$VERILATOR_PATH" ]]; then
  VERILATOR_EXISTS="[${GREEN}✓${NC}]"
fi

if [[ -d "$RISCV" ]]; then
  RISCV_EXISTS="[${GREEN}✓${NC}]"
fi

SPIKE_PATH="$CVA6_REPO/tools/spike"
if [[ -d "$SPIKE_PATH" ]]; then
  SPIKE_EXISTS="[${GREEN}✓${NC}]"
fi

VERILATOR_PATH="$CVA6_REPO/tools/verilator-v5.008"
if [[ -d "$VERILATOR_PATH" ]]; then
  VERILATOR_EXISTS="[${GREEN}✓${NC}]"
fi

echo ""
echo "Status:"
echo "  $CVA6_EXISTS CVA6 Repository: $CVA6_REPO"
echo "  $RISCV_EXISTS RISCV Toolchain: $RISCV"
echo "  $SPIKE_EXISTS Spike: $SPIKE_PATH"
echo "  $VERILATOR_EXISTS Verilator: $VERILATOR_PATH"
echo ""

# ============================================================
# Ask what to remove
# ============================================================
echo "What would you like to remove?"
echo ""

REMOVE_CVA6=false
REMOVE_RISCV=false
REMOVE_SPIKE=false
REMOVE_VERILATOR=false
REMOVE_PYENV_VENV=false
REMOVE_BASHRC=false

if ask_yes_no "Remove CVA6 repository?"; then
  REMOVE_CVA6=true
fi

if ask_yes_no "Remove RISCV toolchain?"; then
  REMOVE_RISCV=true
fi

if ask_yes_no "Remove Spike simulator?"; then
  REMOVE_SPIKE=true
fi

if ask_yes_no "Remove Verilator?"; then
  REMOVE_VERILATOR=true
fi

if ask_yes_no "Remove pyenv virtual environment (cva6)?"; then
  REMOVE_PYENV_VENV=true
fi

if ask_yes_no "Remove CVA6 environment from ~/.bashrc?"; then
  REMOVE_BASHRC=true
fi

echo ""

# ============================================================
# Confirmation before removal
# ============================================================
echo "======================================"
echo "Summary of changes:"
echo "======================================"
if $REMOVE_CVA6; then
  echo "  ${YELLOW}Remove:${NC} $CVA6_REPO"
fi
if $REMOVE_RISCV; then
  echo "  ${YELLOW}Remove:${NC} $RISCV"
fi
if $REMOVE_SPIKE; then
  echo "  ${YELLOW}Remove:${NC} $SPIKE_PATH"
fi
if $REMOVE_VERILATOR; then
  echo "  ${YELLOW}Remove:${NC} $VERILATOR_PATH"
fi
if $REMOVE_PYENV_VENV; then
  echo "  ${YELLOW}Remove:${NC} pyenv virtualenv 'cva6'"
fi
if $REMOVE_BASHRC; then
  echo "  ${YELLOW}Remove:${NC} CVA6 Environment block from ~/.bashrc"
fi
echo ""

if ! ask_yes_no "Proceed with uninstallation?"; then
  echo "Uninstallation cancelled."
  exit 0
fi

# ============================================================
# Perform removal
# ============================================================
echo ""
echo "======================================"
echo "Removing components..."
echo "======================================"
echo ""

if $REMOVE_CVA6; then
  if [[ -d "$CVA6_REPO" ]]; then
    echo "Removing CVA6 repository..."
    rm -rf "$CVA6_REPO"
    echo "  ${GREEN}✓${NC} CVA6 repository removed"
  else
    echo "  ${YELLOW}!${NC} CVA6 repository not found, skipping"
  fi
fi

if $REMOVE_SPIKE; then
  if [[ -d "$SPIKE_PATH" ]]; then
    echo "Removing Spike..."
    rm -rf "$SPIKE_PATH"
    echo "  ${GREEN}✓${NC} Spike removed"
  else
    echo "  ${YELLOW}!${NC} Spike not found, skipping"
  fi
fi

if $REMOVE_VERILATOR; then
  if [[ -d "$VERILATOR_PATH" ]]; then
    echo "Removing Verilator..."
    rm -rf "$VERILATOR_PATH"
    echo "  ${GREEN}✓${NC} Verilator removed"
  else
    echo "  ${YELLOW}!${NC} Verilator not found, skipping"
  fi
fi

if $REMOVE_RISCV; then
  if [[ -d "$RISCV" ]]; then
    echo "Removing RISCV toolchain..."
    rm -rf "$RISCV"
    echo "  ${GREEN}✓${NC} RISCV toolchain removed"
  else
    echo "  ${YELLOW}!${NC} RISCV toolchain not found, skipping"
  fi
fi

if $REMOVE_PYENV_VENV; then
  if command -v pyenv >/dev/null 2>&1; then
    echo "Removing pyenv virtual environment 'cva6'..."
    if pyenv versions 2>/dev/null | grep -q "cva6"; then
      pyenv uninstall -f cva6 2>/dev/null || pyenv uninstall cva6
      echo "  ${GREEN}✓${NC} pyenv virtualenv 'cva6' removed"
    else
      echo "  ${YELLOW}!${NC} pyenv virtualenv 'cva6' not found, skipping"
    fi
  else
    echo "  ${YELLOW}!${NC} pyenv not found, skipping"
  fi
fi

if $REMOVE_BASHRC; then
  echo "Removing CVA6 Environment from ~/.bashrc..."
  if grep -q "# ---- CVA6 Environment ----" "$HOME/.bashrc"; then
    # Remove the CVA6 Environment block
    sed -i '/# ---- CVA6 Environment ----/,/^$/d' "$HOME/.bashrc"
    echo "  ${GREEN}✓${NC} CVA6 Environment removed from ~/.bashrc"
    echo ""
    echo "  ${YELLOW}Note:${NC} Run 'source ~/.bashrc' or open a new terminal"
  else
    echo "  ${YELLOW}!${NC} CVA6 Environment block not found in ~/.bashrc, skipping"
  fi
fi

# ============================================================
# Final message
# ============================================================
echo ""
echo "======================================"
echo "Uninstallation completed"
echo "======================================"
echo ""
echo "If you want to reinstall CVA6, run:"
echo "  bash /$(dirname "$0")/cva6Install.sh"
echo ""
