#!/bin/bash
set -euo pipefail

echo "=== CVA6 Toolchain Installer ==="

# -------------------------------
# Helper functions
# -------------------------------
error_exit() {
    echo "ERROR: $1"
    exit 1
}

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# -------------------------------
# Check gcc exists
# -------------------------------
if ! command -v gcc &> /dev/null; then
    error_exit "gcc not found. Install GCC first."
fi

GCC_VER=$(gcc -dumpversion)
DEFAULT_CONFIG="gcc-${GCC_VER}-BareMetal"

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
        is_integer "$NUM_JOBS" || error_exit "NUM_JOBS must be a number."
        ;;
    *)
        error_exit "Not valid answer."
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
    python3 python3-pip python3-venv cmake

# Optional but recommended: remove asciidoctor warning about pygments
sudo apt-get install -y ruby ruby-dev
sudo gem install pygments.rb

# -------------------------------
# CVA6 directory
# -------------------------------
read -p "Path to CVA6 repository (e.g. ~/cva6): " CVA6_DIR
CVA6_DIR="${CVA6_DIR/#\~/$HOME}"

[ -d "$CVA6_DIR" ] || error_exit "CVA6 directory not found."

cd "$CVA6_DIR"
git submodule update --init --recursive

[ -d "$CVA6_DIR/util/toolchain-builder" ] || error_exit "Invalid CVA6 directory (toolchain-builder missing)."

export CVA6_DIR

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
read -p "Custom config name? (y/n) [default: $DEFAULT_CONFIG]: " opti

case "$opti" in
    y|Y)
        read -p "Enter custom config name: " CONFIG_NAME
        ;;
    n|N|"")
        CONFIG_NAME="$DEFAULT_CONFIG"
        ;;
    *)
        error_exit "Not valid answer."
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
# Apply patch
# -------------------------------
echo "Applying CVA6 GCC patch..."
cd "$CVA6_DIR/util/toolchain-builder/src/gcc"
git apply ../../gcc-cva6-tune.patch

# -------------------------------
# Build toolchain
# -------------------------------
echo "Building toolchain..."
cd "$CVA6_DIR/util/toolchain-builder"
bash build-toolchain.sh "$CONFIG_NAME" "$INSTALL_DIR"

# -------------------------------
# Virtual environment setup
# -------------------------------
echo "Setting up Python virtual environment for CVA6 verification..."

VENV_DIR="$CVA6_DIR/cva6"

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
pip install --upgrade pip

# -------------------------------
# Find requirements file
# -------------------------------
REQ_FILE=$(find "$CVA6_DIR/verif" -name "requirements.txt" | head -n 1 || true)

if [ -z "$REQ_FILE" ]; then
    error_exit "No requirements.txt found in CVA6 repository."
fi

echo "Using requirements file: $REQ_FILE"
pip install -r "$REQ_FILE"

# -------------------------------
# Docs requirements
# -------------------------------
if [ -f "$CVA6_DIR/docs/requirements.txt" ]; then
    pip install -r "$CVA6_DIR/docs/requirements.txt"
else
    error_exit "No docs/requirements.txt found in CVA6 repository."
fi

# Install rstcloth explicitly
pip install rstcloth

# -------------------------------
# Generate documentation (always)
# -------------------------------
echo "Generating project documentation..."
cd "$CVA6_DIR/docs"
make
cd "$CVA6_DIR"

deactivate

# -------------------------------
# Writing virtual env to .bashrc file
# -------------------------------
BASHRC="$HOME/.bashrc"

if ! grep -q "function cva6" "$BASHRC"; then
    echo "" >> "$BASHRC"
    echo "# CVA6 Python virtual environment" >> "$BASHRC"
    echo "function cva6() {" >> "$BASHRC"
    echo "    source \"$VENV_DIR/bin/activate\"" >> "$BASHRC"
    echo "}" >> "$BASHRC"
fi

# -------------------------------
# CVA6 smoke tests (Spike + Verilator)
# -------------------------------
read -p "Run CVA6 smoke tests now? (y/n): " run_tests

if [[ "$run_tests" =~ ^[Yy]$ ]]; then

    SMOKE_SCRIPT="$CVA6_DIR/verif/regress/smoke-gen_tests.sh"

    if [ ! -f "$SMOKE_SCRIPT" ]; then
        error_exit "No smoke-gen_tests.sh found in $CVA6_DIR/verif/regress"
    fi

    echo "Running CVA6 smoke tests using: $SMOKE_SCRIPT"

    source "$VENV_DIR/bin/activate"
    export DV_SIMULATORS=veri-testharness,spike

    bash "$SMOKE_SCRIPT"

    deactivate
else
    echo "Skipping smoke tests."
fi

# -------------------------------
# Final user instructions
# -------------------------------
echo ""
echo "=== INSTALLATION COMPLETE ==="
echo ""
echo "To activate the CVA6 Python virtual environment, run:"
echo "  cva6"
echo ""
echo "To deactivate, run:"
echo "  deactivate"
echo ""
echo "To regenerate documentation later:"
echo "  cva6"
echo "  cd $CVA6_DIR/docs"
echo "  make"
echo "  deactivate"
echo ""
echo "Happy RISC-Ving!"
echo "============================="
