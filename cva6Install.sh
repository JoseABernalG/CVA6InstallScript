#!/bin/bash
set -e

echo "=== CVA6 Toolchain Installer ==="

# -------------------------------
# Threads
# -------------------------------
read -p "Use all available threads? (y/n): " opti

case "$opti" in
    y|Y)
        NUM_JOBS=$(nproc)
        ;;
    n|N)
        read -p "Enter number of threads: " NUM_JOBS
        ;;
    *)
        echo "Not valid answer."
        exit 1
        ;;
esac

export NUM_JOBS
echo "Using $NUM_JOBS threads"

# -------------------------------
# Prerequisites
# -------------------------------
echo "Installing prerequisites..."

sudo apt-get update
sudo apt-get install -y \
    autoconf automake autotools-dev curl git \
    libmpc-dev libmpfr-dev libgmp-dev gawk \
    build-essential bison flex texinfo gperf \
    libtool bc zlib1g-dev help2man device-tree-compiler \
    python3 python3-pip python3-venv

# -------------------------------
# CVA6 directory
# -------------------------------
echo
read -p "Path to CVA6 repository (e.g. ~/cva6): " CVA6_DIR
CVA6_DIR="${CVA6_DIR/#\~/$HOME}"

[ -d "$CVA6_DIR/util/toolchain-builder" ] || {
    echo "Invalid CVA6 directory"
    exit 1
}

export CVA6_DIR

echo "Initializing CVA6 submodules..."
cd "$CVA6_DIR"
git submodule update --init --recursive

# -------------------------------
# RISCV install directory
# -------------------------------
read -p "Path to RISC-V toolchain install directory (e.g. ~/riscv): " RISCV
RISCV="${RISCV/#\~/$HOME}"

export RISCV
INSTALL_DIR="$RISCV"
export INSTALL_DIR

mkdir -p "$INSTALL_DIR"

# -------------------------------
# Config name
# -------------------------------
read -p "Custom config name? (y/n) [default: gcc-13.3.0-BareMetal]: " opti

case "$opti" in
    y|Y)
        read -p "Enter custom config name: " CONFIG_NAME
        ;;
    n|N|"")
        CONFIG_NAME="gcc-13.3.0-BareMetal"
        ;;
    *)
        echo "Not valid answer."
        exit 1
        ;;
esac

export CONFIG_NAME
echo "Using config: $CONFIG_NAME"

# -------------------------------
# Fetch toolchain
# -------------------------------
echo "Fetching toolchain sources..."
bash "$CVA6_DIR/util/toolchain-builder/get-toolchain.sh"

# -------------------------------
# Apply patch (idempotent)
# -------------------------------
echo "Applying CVA6 GCC patch..."
cd "$CVA6_DIR/util/toolchain-builder/src/gcc"

if git apply --check ../../gcc-cva6-tune.patch 2>/dev/null; then
    git apply ../../gcc-cva6-tune.patch
else
    echo "Patch already applied or not applicable, skipping."
fi

# -------------------------------
# Build toolchain
# -------------------------------
echo "Building toolchain..."
cd "$CVA6_DIR/util/toolchain-builder"
bash build-toolchain.sh "$CONFIG_NAME" "$INSTALL_DIR"

# -------------------------------
# Python virtual environment (cva6)
# -------------------------------
echo "Setting up Python virtual environment for CVA6 verification..."

VENV_DIR="$CVA6_DIR/venv-cva6"

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# Activate venv temporarily to install deps
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip
python -m pip install -r "$CVA6_DIR/verif/sim/dv/requirements.txt"

deactivate

# -------------------------------
# Write venv activation helper to .bashrc
# -------------------------------
BASHRC="$HOME/.bashrc"

if ! grep -q "activate_cva6()" "$BASHRC"; then
    {
        echo ""
        echo "# CVA6 Python virtual environment"
        echo "activate_cva6() {"
        echo "    source \"$VENV_DIR/bin/activate\""
        echo "}"
    } >> "$BASHRC"
fi

# -------------------------------
# CVA6 smoke tests (Spike + Verilator)
# -------------------------------
read -p "Run CVA6 smoke tests now? (y/n): " run_tests

if [[ "$run_tests" =~ ^[Yy]$ ]]; then
    echo "Running CVA6 smoke tests (Spike + Verilator)..."
    cd "$CVA6_DIR"
    source "$VENV_DIR/bin/activate"
    export DV_SIMULATORS=veri-testharness,spike
    bash verif/regress/smoke-tests.sh
    deactivate
else
    echo "Skipping smoke tests."
fi

# -------------------------------
# Final message
# -------------------------------
echo
echo "=== DONE ==="
echo "To activate the CVA6 Python environment later, run:"
echo "  activate_cva6"
