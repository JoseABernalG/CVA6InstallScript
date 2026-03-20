#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Helpers
# ============================================================
log_step() {
    echo ""
    echo "=============================================="
    echo "  $1"
    echo "=============================================="
}

expand_path() {
  [[ "$1" == "~"* ]] && echo "${1/#\~/$HOME}" || echo "$1"
}

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

# Enable tab completion for path inputs
bind 'set completion-ignore-case on' 2>/dev/null || true

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
echo ""
echo "Enter paths (use TAB for autocomplete):"
echo ""
# Use -e to enable readline (tab completion)
if [ -t 0 ]; then
  read -e -p "Enter CVA6 repo path (e.g., ~/cva6): " CVA6_REPO
  read -e -p "Enter RISCV install path (e.g., ~/riscv): " RISCV
else
  read -p "Enter CVA6 repo path (e.g., ~/cva6): " CVA6_REPO
  read -p "Enter RISCV install path (e.g., ~/riscv): " RISCV
fi

CVA6_REPO=$(realpath "$(expand_path "$CVA6_REPO")")
RISCV=$(realpath "$(expand_path "$RISCV")")

[[ ! -d "$CVA6_REPO" ]] && echo "ERROR: CVA6 repo not found" && exit 1
mkdir -p "$RISCV"

export RISCV INSTALL_DIR="$RISCV"

# ============================================================
# Threads
# ============================================================
echo ""
while true; do
  read -p "Use all available threads? (y/n): " opti
  case "$opti" in
    y|Y) 
      NUM_JOBS=$(nproc)
      break
      ;;
    n|N)
      read -p "Enter number of threads: " NUM_JOBS
      break
      ;;
    *)
      echo "  Please answer 'y' (yes) or 'n' (no)."
      ;;
  esac
done

export NUM_JOBS
echo "Using $NUM_JOBS build threads"

# ============================================================
# System dependencies (verified)
# ============================================================
log_step "Installing system dependencies"
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
else
  echo "✓ bytefield-svg is already installed"
fi

if ! command -v wavedrom-cli >/dev/null 2>&1; then
  echo "Installing wavedrom-cli..."
  sudo npm install -g wavedrom-cli
else
  echo "✓ wavedrom-cli is already installed"
fi

# ============================================================
# Ruby gems (docs)
# ============================================================
if ask_yes_no "Install documentation tools (Ruby + Asciidoctor)?"; then
  echo "Installing Ruby gems for documentation..."
  sudo gem install \
    asciidoctor \
    asciidoctor-bibtex \
    asciidoctor-diagram \
    asciidoctor-lists \
    asciidoctor-mathematical \
    pygments.rb
  echo "✓ Ruby gems installed"
fi

# ============================================================
# GCC config name
# ============================================================
GCC_VER=$(gcc -dumpversion 2>/dev/null || echo "unknown")
DEFAULT_CONFIG_NAME="gcc-${GCC_VER}-BareMetal"

echo ""
echo "Detected GCC-based config name:"
echo "  $DEFAULT_CONFIG_NAME"
while true; do
  read -p "Use this config name? (y/n) [default]: " opti
  case "$opti" in
    y|Y|"")
      CONFIG_NAME="$DEFAULT_CONFIG_NAME"
      break
      ;;
    n|N)
      read -p "Enter custom config name: " CONFIG_NAME
      break
      ;;
    *)
      echo "  Please answer 'y' (yes) or 'n' (no)."
      ;;
  esac
done

export CONFIG_NAME
echo "Using config name: $CONFIG_NAME"

# ============================================================
# Python virtual environment (using pyenv)
# ============================================================
USE_PYTHON=false
if ask_yes_no "Use Python virtual environment (cva6)?"; then
  USE_PYTHON=true
  
  # Set up pyenv
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  
  # Check if pyenv is installed
  if [[ ! -f "$PYENV_ROOT/bin/pyenv" ]]; then
    echo "ERROR: pyenv is not installed at $PYENV_ROOT"
    echo "Visit: https://github.com/pyenv/pyenv#installation"
    exit 1
  fi
  
  # Initialize pyenv
  eval "$(pyenv init -)" 2>/dev/null || true
  eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
  
  # Verify pyenv virtualenv is available
  if ! pyenv virtualenvs >/dev/null 2>&1; then
    echo "ERROR: pyenv-virtualenv plugin is not installed."
    echo "Visit: https://github.com/pyenv/pyenv-virtualenv#installation"
    exit 1
  fi
  
  # Detect Python version from system
  PYTHON_VERSION=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))" 2>/dev/null || echo "3.10")
  
  # Check if Python version is available in pyenv (don't install, just check)
  VENV_NAME="cva6"
  if [[ -d "$HOME/.pyenv/versions/$VENV_NAME" ]]; then
    echo "Using existing Python venv '$VENV_NAME'..."
  else
    echo "ERROR: Python venv '$VENV_NAME' not found."
    echo "Please create it first with: pyenv virtualenv $PYTHON_VERSION $VENV_NAME"
    exit 1
  fi
  
  # Activate the virtual environment for this session
  echo "Activating Python venv '$VENV_NAME'..."
  export VIRTUAL_ENV="$HOME/.pyenv/versions/$VENV_NAME"
  export PATH="$VIRTUAL_ENV/bin:$PATH"
  echo "✓ Python virtual environment activated"
fi

# ============================================================
# Git + toolchain
# ============================================================
log_step "Building RISC-V toolchain (GCC)"
cd "$CVA6_REPO"
echo "Initializing git submodules..."
git submodule update --init --recursive

echo "Fetching toolchain sources..."
bash util/toolchain-builder/get-toolchain.sh

echo "Applying CVA6 GCC patch..."
cd util/toolchain-builder/src/gcc
git apply ../../gcc-cva6-tune.patch || echo "Patch already applied or not found"

echo "Building toolchain..."
cd "$CVA6_REPO/util/toolchain-builder"
bash build-toolchain.sh "$CONFIG_NAME" "$INSTALL_DIR"

# ============================================================
# Python requirements
# ============================================================
if $USE_PYTHON; then
  log_step "Installing Python requirements"
  pip install -r "$CVA6_REPO/verif/sim/dv/requirements.txt"
  pip install -r "$CVA6_REPO/docs/requirements.txt"
  pip install rstcloth mako mdutils recommonmark
fi


# ============================================================
# Fix documentation bug (missing endif in machine.adoc)
# Must run before toolchain/doc build
# ============================================================
MACHINE_ADOC="$CVA6_REPO/docs/riscv-isa/src/machine.adoc"

echo "Checking machine.adoc preprocessor directives..."

if [[ -f "$MACHINE_ADOC" ]]; then
    LINE_CONTENT=$(sed -n '3114p' "$MACHINE_ADOC")

    if [[ "$LINE_CONTENT" != *"endif::[]"* ]]; then
        echo "Fixing missing endif::[] in machine.adoc (line 3114)..."
        sed -i '3114a endif::[]' "$MACHINE_ADOC"
        echo "Patch applied."
    else
        echo "machine.adoc already correct."
    fi
else
    echo "WARNING: machine.adoc not found, skipping fix."
fi

# ============================================================
# Copy missing cv64a6_mmu_config_pkg.sv
# ============================================================
SRC_FILE="$CVA6_REPO/core/include/deprecated_packages/cv64a6_mmu_config_pkg.sv"
DEST_FILE="$CVA6_REPO/core/include/cv64a6_mmu_config_pkg.sv"

if [[ -f "$DEST_FILE" ]]; then
    echo "cv64a6_mmu_config_pkg.sv already exists, skipping copy."
else
    if [[ -f "$SRC_FILE" ]]; then
        echo "Copying cv64a6_mmu_config_pkg.sv..."
        cp "$SRC_FILE" "$DEST_FILE"
        echo "Done."
    else
        echo "WARNING: Source file not found: $SRC_FILE"
    fi
fi

# ============================================================
# Docs build
# ============================================================
if ask_yes_no "Build documentation now?"; then
  log_step "Building documentation"
  cd "$CVA6_REPO/docs"
  make
  echo "✓ Documentation built successfully"
fi

# ------------------------------------------------------------
# Configuration-specific manuals (optional)
# ------------------------------------------------------------
if ask_yes_no "Build configuration-specific manuals?"; then
  log_step "Building configuration-specific manuals"
  cd "$CVA6_REPO/docs"
  
  # Instruction set manuals (privileged & unprivileged)
  echo "Building instruction set manuals..."
  make -C 04_cv32a65x/riscv priv-html unpriv-html 2>/dev/null || echo "Warning: Could not build riscv manuals"
  
  # Design documentation
  echo "Building design documentation..."
  make -C 04_cv32a65x/design design-html 2>/dev/null || echo "Warning: Could not build design docs"
  
  echo "✓ Configuration-specific manuals built"
fi

# ============================================================
# Install Verilator and Spike using CVA6 official scripts
# ============================================================
log_step "Installing Verilator and Spike"
cd "$CVA6_REPO"

# Install Verilator (uses v5.008 with required patch for CVA6)
echo "Installing Verilator..."
export VERILATOR_INSTALL_DIR="$CVA6_REPO/tools/verilator-v5.008"
bash verif/regress/install-verilator.sh

# Create symlinks for Verilator auxiliary scripts (make install puts them in share/verilator/bin/)
echo "Creating symlinks for Verilator auxiliary scripts..."
ln -sf "$VERILATOR_INSTALL_DIR/share/verilator/bin/verilator_includer" "$VERILATOR_INSTALL_DIR/bin/verilator_includer"
ln -sf "$VERILATOR_INSTALL_DIR/share/verilator/bin/verilator_ccache_report" "$VERILATOR_INSTALL_DIR/bin/verilator_ccache_report"
ln -sf "$VERILATOR_INSTALL_DIR/share/verilator/bin/verilator_difftree" "$VERILATOR_INSTALL_DIR/bin/verilator_difftree"
echo "✓ Verilator symlinks created"

if [ ! -e "$VERILATOR_INSTALL_DIR/include" ]; then
  ln -s "$VERILATOR_INSTALL_DIR/share/verilator/include" "$VERILATOR_INSTALL_DIR/include"
fi

# Set Verilator environment variables BEFORE installing Spike
export VERILATOR_ROOT="$VERILATOR_INSTALL_DIR"

# Install Spike (uses vendorized version in CVA6 repo)
echo "Installing Spike..."
bash verif/regress/install-spike.sh

# Get the actual installation paths
SPIKE_INSTALL_DIR="$CVA6_REPO/tools/spike"

# Verify installations
if [[ -f "$VERILATOR_INSTALL_DIR/bin/verilator" ]]; then
  VERILATOR_VERSION=$("$VERILATOR_INSTALL_DIR/bin/verilator" --version 2>&1 || echo "unknown")
  echo "✓ Verilator installed: $VERILATOR_VERSION"
else
  echo "WARNING: Verilator installation may have failed"
fi

if [[ -f "$SPIKE_INSTALL_DIR/bin/spike" ]]; then
  SPIKE_VERSION=$("$SPIKE_INSTALL_DIR/bin/spike" --version 2>&1 || echo "unknown")
  echo "✓ Spike installed: $SPIKE_VERSION"
else
  echo "WARNING: Spike installation may have failed"
fi

# ============================================================
# Smoke tests
# ============================================================
# Source setup-env.sh BEFORE smoke tests to ensure environment is configured
export VERILATOR_ROOT="$VERILATOR_INSTALL_DIR"
export DPI_STD_PATH="$VERILATOR_INSTALL_DIR/include/vltstd"
export DPI_INCLUDE_PATH="$VERILATOR_INSTALL_DIR/include"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export PATH="$RISCV/bin:$PATH"
export CV_SW_PREFIX="${CV_SW_PREFIX:-riscv-none-elf-}"
export RISCV_CC="${RISCV_CC:-$RISCV/bin/${CV_SW_PREFIX}gcc}"
export RISCV_OBJCOPY="${RISCV_OBJCOPY:-$RISCV/bin/${CV_SW_PREFIX}objcopy}"
export SPIKE_SRC_DIR="${SPIKE_SRC_DIR:-$CVA6_REPO/verif/core-v-verif/vendor/riscv/riscv-isa-sim}"
export SPIKE_INSTALL_DIR="$SPIKE_INSTALL_DIR"

# Source setup-env.sh for simulations
if ask_yes_no "Source setup-env.sh for simulations?"; then
  source verif/sim/setup-env.sh
  echo "✓ setup-env.sh sourced"
fi

if ask_yes_no "Run smoke tests now?"; then
  log_step "Running smoke tests"
  if $USE_PYTHON; then

    echo "Running smoke-gen_tests.sh..."
    cd "$CVA6_REPO"
    bash verif/regress/smoke-gen_tests.sh
    echo "✓ Smoke-gen_tests.sh completed"

    echo ""
    echo "Running individual core smoke tests..."

    echo "Running smoke-tests-cv32a65x.sh..."
    bash verif/regress/smoke-tests-cv32a65x.sh || echo "Warning: cv32a65x tests failed or not found"

    echo "Running smoke-tests-cv32a6_imac_sv32.sh..."
    bash verif/regress/smoke-tests-cv32a6_imac_sv32.sh || echo "Warning: cv32a6_imac_sv32 tests failed or not found"

    echo "Running smoke-tests-cv64a6_imafdc_sv39.sh..."
    bash verif/regress/smoke-tests-cv64a6_imafdc_sv39.sh || echo "Warning: cv64a6_imafdc_sv39 tests failed or not found"

    echo "✓ Individual core smoke tests completed"
  fi
  echo "✓ Smoke tests completed"
else
  echo "Skipping smoke tests."
fi

# ============================================================
# Standalone Simulations (examples)
# ============================================================
log_step "Running standalone simulations"

# Default verification environment variables
DV_TARGET="cv64a6_imafdc_sv39"
DV_SIMULATORS="veri-testharness,spike"
DV_TESTLISTS="../tests/testlist_riscv-tests-$DV_TARGET-p.yaml ../tests/testlist_riscv-tests-$DV_TARGET-v.yaml"

# Note: setup-env.sh has already been sourced in the previous section
if [[ -z "$RISCV_CC" ]]; then
  echo "WARNING: setup-env.sh may not have been sourced. Sourcing now..."
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
  export PATH="$RISCV/bin:$PATH"
  export CV_SW_PREFIX="${CV_SW_PREFIX:-riscv-none-elf-}"
  export RISCV_CC="${RISCV_CC:-$RISCV/bin/${CV_SW_PREFIX}gcc}"
  export RISCV_OBJCOPY="${RISCV_OBJCOPY:-$RISCV/bin/${CV_SW_PREFIX}objcopy}"
  source verif/sim/setup-env.sh
fi

# Hello World simulation
if ask_yes_no "Run hello_world simulation?"; then
  export DV_SIMULATORS="veri-testharness"
  cd ./verif/sim
  python3 cva6.py --target cv32a60x --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml \
    --c_tests ../tests/custom/hello_world/hello_world.c \
    --linker=../../config/gen_from_riscv_config/linker/link.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -nostdlib \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S -lgcc \
    -I../tests/custom/env -I../tests/custom/common"
  cd "$CVA6_REPO"
  echo "✓ hello_world simulation completed"
fi

# RISC-V Proxy Kernel simulation (for printf support)
if ask_yes_no "Run veri-testharness-pk simulation?"; then
  export DV_SIMULATORS="veri-testharness-pk"
  bash verif/regress/veri-testharness-pk-tests.sh
  echo "✓ veri-testharness-pk simulation completed"
fi

# Regression tests
if ask_yes_no "Run riscv-arch-test regression suite?"; then
  export DV_SIMULATORS="veri-testharness,spike"
  bash verif/regress/dv-riscv-arch-test.sh
  echo "✓ riscv-arch-test regression completed"
fi

# Waveform generation (optional - uncomment to enable)
# export TRACE_FAST=1
# echo "✓ TRACE_FAST=1 enabled (VCD/FST files will be generated)"
# echo "  Logs and waveforms: ./verif/sim/out_YEAR-MONTH-DAY/"

# Coverage is disabled by default (VCS only)
# Uncomment the following lines to enable coverage:
# export cov=1

# Log files info
echo ""
echo "Log files location: ./verif/sim/out_YEAR-MONTH-DAY/"
echo "  - directed_asm_tests/: compiled assembly tests"
echo "  - directed_c_tests/: compiled C tests"
echo "  - spike_sim/: Spike simulation logs"
echo "  - veri_testharness_sim/: Verilator simulation logs"
echo "  - veri-testharness-pk_sim/: Proxy kernel simulation logs"
echo "  - iss_regr.log: Regression test comparison log"

# ============================================================
# Environment persistence
# ============================================================
if ask_yes_no "Add CVA6, RISCV, Verilator, and Spike to ~/.bashrc?"; then
  if ! grep -q "CVA6 Environment" "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" << EOF

# ---- CVA6 Environment ----

# Pyenv configuration for Python virtual environment
export PATH="~/.pyenv/bin:$PATH"
export PATH="~/.pyenv/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# CVA6 Environment Variables
export CVA6_REPO_DIR="$CVA6_REPO"
export RISCV="$RISCV"
export INSTALL_DIR="$RISCV"
export CV_SW_PREFIX="${CV_SW_PREFIX:-riscv-none-elf-}"
export VERILATOR_ROOT="$VERILATOR_INSTALL_DIR"
export VERILATOR_INSTALL_DIR="$VERILATOR_INSTALL_DIR"
export SPIKE_ROOT="$SPIKE_INSTALL_DIR"
export SPIKE_SRC_DIR="$CVA6_REPO/verif/core-v-verif/vendor/riscv/riscv-isa-sim"
export SPIKE_INSTALL_DIR="$SPIKE_INSTALL_DIR"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export CV_SW_PREFIX="${CV_SW_PREFIX:-riscv-none-elf-}"
export RISCV_CC="${RISCV_CC:-$RISCV/bin/${CV_SW_PREFIX}gcc}"
export RISCV_OBJCOPY="${RISCV_OBJCOPY:-$RISCV/bin/${CV_SW_PREFIX}objcopy}"
export DPI_STD_PATH="$VERILATOR_INSTALL_DIR/include/vltstd"
export DPI_INCLUDE_PATH="$VERILATOR_INSTALL_DIR/include"
export DV_SIMULATORS="veri-testharness,spike"
export DV_TARGET=cv64a6_imafdc_sv39
export DV_TESTLISTS="../tests/testlist_riscv-tests-\$DV_TARGET-p.yaml ../tests/testlist_riscv-tests-\$DV_TARGET-v.yaml"
export TRACE_FAST=1

# Add to PATH
export PATH="$VERILATOR_INSTALL_DIR/bin:$PATH"
export PATH="$SPIKE_INSTALL_DIR/bin:$PATH"
export PATH="$RISCV/bin:$PATH"

# Verdi is disabled by default (conflicts with TRACE_FAST)
# Don't export VERDI=0 as it conflicts with TRACE_FAST in Makefile

# To activate Python venv: pyenv activate cva6

EOF

    echo "✓ CVA6 environment added to ~/.bashrc"
  else
    echo "✓ CVA6 environment already present in ~/.bashrc"
  fi
fi

# Export minimal variables for current session
export RISCV="$RISCV"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export CV_SW_PREFIX="${CV_SW_PREFIX:-riscv-none-elf-}"

# Source CVA6 simulation environment
if [ -f "$CVA6_REPO/verif/sim/setup-env.sh" ]; then
    source "$CVA6_REPO/verif/sim/setup-env.sh"
fi

# Default simulation settings
export DV_SIMULATORS="veri-testharness,spike"
export DV_TARGET=cv64a6_imafdc_sv39
export DV_TESTLISTS="../tests/testlist_riscv-tests-\$DV_TARGET-p.yaml ../tests/testlist_riscv-tests-\$DV_TARGET-v.yaml"

# Add Verilator to PATH
case ":$PATH:" in
  *":$VERILATOR_INSTALL_DIR/bin:"*) ;;
  *) export PATH="$VERILATOR_INSTALL_DIR/bin:$PATH" ;;
esac

# Add Spike to PATH
case ":$PATH:" in
  *":$SPIKE_INSTALL_DIR/bin:"*) ;;
  *) export PATH="$SPIKE_INSTALL_DIR/bin:$PATH" ;;
esac

# Add RISCV toolchain to PATH
case ":$PATH:" in
  *":$RISCV/bin:"*) ;;
  *) export PATH="$RISCV/bin:$PATH" ;;
esac

# ============================================================
# Deactivate virtual environment
# ============================================================
if $USE_PYTHON; then
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    deactivate 2>/dev/null || true
    unset VIRTUAL_ENV
  fi
fi

# ============================================================
# Final message
# ============================================================
echo ""
echo "======================================"
echo "CVA6 installation completed successfully"
echo "======================================"
echo ""
echo "Installation paths:"
echo "  CVA6_REPO     : $CVA6_REPO"
echo "  RISCV         : $RISCV"
echo "  Verilator     : $VERILATOR_INSTALL_DIR"
echo "  Spike         : $SPIKE_INSTALL_DIR"
echo ""
echo "Toolchain config: $CONFIG_NAME"
echo ""
echo "DV_SIMULATORS  : veri-testharness,spike"
echo "DV_TARGET      : cv64a6_imafdc_sv39"
echo ""
echo "NOTE: TRACE_FAST and VERDI are mutually exclusive!"
echo "      TRACE_FAST=1 is enabled in ~/.bashrc by default."
echo "      To use VERDI instead, comment TRACE_FAST and uncomment VERDI in ~/.bashrc"
echo ""
echo "To activate Python venv:"
echo "  pyenv activate cva6"
echo ""
echo "To set environment for future sessions:"
echo "  The environment is already configured in ~/.bashrc"
echo "  Run: source ~/.bashrc"
echo ""
echo "======================================"
echo "UNINSTALL INSTRUCTIONS:"
echo "======================================"
echo ""
echo "To uninstall CVA6, run:"
echo "  bash $(dirname "$0")/cva6Uninstall.sh"
echo ""
echo "======================================"

