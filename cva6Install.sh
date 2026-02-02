#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Helpers
# ============================================================
expand_path() {
  [[ "$1" == "~"* ]] && echo "${1/#\~/$HOME}" || echo "$1"
}

ask_yes_no() {
  local prompt="$1"
  read -p "$prompt (y/n): " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_packages() {
  local missing=()
  for pkg in "$@"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done

  if (( ${#missing[@]} > 0 )); then
    echo ""
    echo "Installing missing system packages:"
    echo "  ${missing[*]}"
    sudo apt update
    sudo apt install -y "${missing[@]}"
  else
    echo "✓ All required system packages are already installed"
  fi
}

# ============================================================
# Paths
# ============================================================
read -p "Enter CVA6 repo path (e.g., ~/cva6): " CVA6_REPO
read -p "Enter RISCV install path (e.g., ~/riscv): " RISCV

CVA6_REPO=$(realpath "$(expand_path "$CVA6_REPO")")
RISCV=$(realpath "$(expand_path "$RISCV")")

[[ ! -d "$CVA6_REPO" ]] && echo "ERROR: CVA6 repo not found" && exit 1
mkdir -p "$RISCV"

export RISCV INSTALL_DIR="$RISCV"


# ============================================================
# Fix documentation bug (missing endif in machine.adoc)
# Must run before toolchain/doc build
# ============================================================

MACHINE_ADOC="$CVA6_REPO/docs/riscv-isa/src/machine.adoc"

echo "Checking machine.adoc preprocessor directives..."

if [[ -f "$MACHINE_ADOC" ]]; then
    LINE_CONTENT=$(sed -n '114p' "$MACHINE_ADOC")

    if [[ "$LINE_CONTENT" != *"endif::[]"* ]]; then
        echo "Fixing missing endif::[] in machine.adoc (line 114)..."
        sed -i '114a endif::[]' "$MACHINE_ADOC"
        echo "Patch applied."
    else
        echo "machine.adoc already correct."
    fi
else
    echo "WARNING: machine.adoc not found, skipping fix."
fi


# ============================================================
# Threads
# ============================================================
echo ""
read -p "Use all available threads? (y/n): " opti
case "$opti" in
  y|Y) NUM_JOBS=$(nproc) ;;
  n|N)
    read -p "Enter number of threads: " NUM_JOBS
    ;;
  *)
    echo "Invalid option"
    exit 1
    ;;
esac

export NUM_JOBS
echo "Using $NUM_JOBS build threads"

# ============================================================
# System dependencies (verified)
# ============================================================
echo ""
echo "Checking system dependencies..."

require_packages \
  autoconf automake autotools-dev curl git gawk \
  build-essential bison flex texinfo gperf \
  libmpc-dev libmpfr-dev libgmp-dev libtool bc \
  zlib1g-dev help2man device-tree-compiler \
  python3 python3-pip python3-venv \
  ruby ruby-dev cmake pkg-config \
  texlive-latex-base texlive-latex-extra texlive-fonts-recommended \
  pkg-config libxml2-dev libxslt1-dev zlib1g-dev libglib2.0-dev \
  libcairo2-dev libpango1.0-dev libgdk-pixbuf2.0-dev libpixman-1-dev \
  nodejs npm

# ------------------------------------------------------------
# Install documentation image generators (Node.js tools)
# ------------------------------------------------------------
if ! command -v bytefield-svg >/dev/null 2>&1; then
  echo "Installing bytefield-svg..."
  sudo npm install -g bytefield-svg
fi

if ! command -v wavedrom-cli >/dev/null 2>&1; then
  echo "Installing wavedrom-cli..."
  sudo npm install -g wavedrom-cli
fi



# ============================================================
# GCC config name
# ============================================================
GCC_VER=$(gcc -dumpversion 2>/dev/null || echo "unknown")
DEFAULT_CONFIG_NAME="gcc-${GCC_VER}-BareMetal"

echo ""
echo "Detected GCC-based config name:"
echo "  $DEFAULT_CONFIG_NAME"
read -p "Use this config name? (y/n) [default]: " opti

case "$opti" in
  y|Y|"")
    CONFIG_NAME="$DEFAULT_CONFIG_NAME"
    ;;
  n|N)
    read -p "Enter custom config name: " CONFIG_NAME
    ;;
  *)
    echo "Invalid option"
    exit 1
    ;;
esac

export CONFIG_NAME
echo "Using config name: $CONFIG_NAME"

# ============================================================
# Python virtual environment
# ============================================================
USE_PYTHON=false
if ask_yes_no "Use Python virtual environment (ScammaCVA6)?"; then
  USE_PYTHON=true
  cd "$HOME"
  if [[ ! -d ScammaCVA6 ]]; then
    echo "Creating Python venv: ScammaCVA6"
    python3 -m venv ScammaCVA6
  fi
  source ScammaCVA6/bin/activate
  pip install --upgrade pip
  pip install rstcloth
  pip install mako
  pip install mdutils

fi

# ============================================================
# Git + toolchain
# ============================================================
cd "$CVA6_REPO"
git submodule update --init --recursive

echo "Fetching toolchain sources..."
bash util/toolchain-builder/get-toolchain.sh

echo "Applying CVA6 GCC patch..."
cd util/toolchain-builder/src/gcc
git apply ../../gcc-cva6-tune.patch || true

echo "Building toolchain..."
cd "$CVA6_REPO/util/toolchain-builder"
bash build-toolchain.sh "$CONFIG_NAME" "$INSTALL_DIR"

# ============================================================
# Python requirements
# ============================================================
if $USE_PYTHON; then
  echo "Installing Python requirements..."
  pip install -r "$CVA6_REPO/verif/sim/dv/requirements.txt"
  pip install -r "$CVA6_REPO/docs/requirements.txt"
fi

# ============================================================
# Ruby gems (docs)
# ============================================================
if ask_yes_no "Install documentation tools (Ruby + Asciidoctor)?"; then
  deactivate 2>/dev/null || true

  echo "Installing Ruby gems for documentation..."
  sudo gem install \
    asciidoctor \
    asciidoctor-bibtex \
    asciidoctor-diagram \
    asciidoctor-lists \
    asciidoctor-mathematical \
    pygments.rb
fi

# =========================
# Environment setup
# =========================

# Use Verilator as simulator instead of VCS
export DV_SIMULATORS=verilator

# Optional: set verbosity (can be overridden later)
export UVM_VERBOSITY=UVM_NONE

# =========================
# Tool installation & smoke tests
# =========================

# -----------------------------
# Ensure LD_LIBRARY_PATH exists to avoid unbound variable errors
# -----------------------------
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"

# -----------------------------
# Add Verilator include path so vpi_user.h and svdpi.h are found
# -----------------------------
VERILATOR_INCLUDE="$CVA6_REPO/tools/verilator-v5.008/share/verilator/include"
export C_INCLUDE_PATH="$VERILATOR_INCLUDE${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
export CPLUS_INCLUDE_PATH="$VERILATOR_INCLUDE${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"


# Install/verifies Verilator
cd "$CVA6_REPO"

bash verif/regress/install-verilator.sh

# Install/verifies Spike
bash verif/regress/install-spike.sh

# Setup simulation environment
source verif/sim/setup-env.sh

# =========================
# Run smoke tests using Verilator
# =========================

read -p "Run smoke tests now? (y/n): " run_smoke
if [[ "$run_smoke" =~ ^[Yy]$ ]]; then
    echo "Running smoke tests with Verilator..."
    bash verif/regress/smoke-gen_tests.sh
else
    echo "Skipping smoke tests."
fi


# ============================================================
# Smoke tests
# ============================================================
if ask_yes_no "Run smoke tests now?"; then
  $USE_PYTHON && source "$HOME/ScammaCVA6/bin/activate"

  echo "Forcing Verilator smoke tests..."
  export DV_SIMULATORS=veri-testharness,spike
  export DV_SIMULATOR=veri-testharness

  cd "$CVA6_REPO"
fi
# -----------------------------
# Ensure LD_LIBRARY_PATH is always defined (avoids "unbound variable" errors)
# and add Verilator include path so vpi_user.h is found
# -----------------------------
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"

# Add Verilator include path to C_INCLUDE_PATH and CPLUS_INCLUDE_PATH
if [ -n "$VERILATOR_INSTALL_DIR" ]; then
    export C_INCLUDE_PATH="$VERILATOR_INSTALL_DIR/include${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
    export CPLUS_INCLUDE_PATH="$VERILATOR_INSTALL_DIR/include${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"

  bash verif/regress/smoke-gen_tests.sh
fi


# ============================================================
# Docs build
# ============================================================
if ask_yes_no "Build documentation now?"; then
  cd "$CVA6_REPO/docs"
  make
fi

# ============================================================
# Persist RISCV + PATH
# ============================================================
if ask_yes_no "Add RISCV and toolchain to ~/.bashrc?"; then
  if ! grep -q "RISC-V Toolchain (CVA6)" "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" << EOF

# ---- RISC-V Toolchain (CVA6) ----
export RISCV="$RISCV"
case ":\$PATH:" in
  *":\$RISCV/bin:"*) ;;
  *) export PATH="\$RISCV/bin:\$PATH" ;;
esac
EOF
    echo "✓ RISC-V environment added to ~/.bashrc"
  else
    echo "✓ RISC-V environment already present in ~/.bashrc"
  fi
fi

# ============================================================
# Final message
# ============================================================
echo ""
echo "======================================"
echo "CVA6 installation completed successfully"
echo ""
echo "Toolchain config : $CONFIG_NAME"
echo "RISCV path       : $RISCV"
echo ""
echo "Activate Python venv:"
echo "  source ~/ScammaCVA6/bin/activate"
echo "======================================"

echo ""
echo "---------------------------------------------------"
echo "Reminder: If you want to manually set environment for future sessions:"
echo "  export LD_LIBRARY_PATH=\"\$LD_LIBRARY_PATH\""
echo "  export C_INCLUDE_PATH=\"$VERILATOR_INCLUDE:\$C_INCLUDE_PATH\""
echo "  export CPLUS_INCLUDE_PATH=\"$VERILATOR_INCLUDE:\$CPLUS_INCLUDE_PATH\""
echo "You can add these lines to your ~/.bashrc or ~/.zshrc"
echo "---------------------------------------------------"


# Example commands to build docs:



#exit 0
#make -C 04_cv32a65x/design design-html

#rm -Rf cva6 RISCV && mkdir RISCV
#git clone https://github.com/openhwgroup/cva6.git
#./CVA6InstallScript/cva6Install.sh
