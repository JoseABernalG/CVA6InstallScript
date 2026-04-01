#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Check for Xilinx Vivado settings and disable during installation
# ============================================================
echo ""
echo "=============================================="
echo "  Xilinx Vivado Detection"
echo "=============================================="
VIVADO_LINE=$(grep -n "source.*settings64" "$HOME/.bashrc" 2>/dev/null | head -1 || true)
if [[ -n "$VIVADO_LINE" ]]; then
  VIVADO_LINENUM=$(echo "$VIVADO_LINE" | cut -d: -f1)
  echo "NOTE: Found Vivado settings in ~/.bashrc (line $VIVADO_LINENUM)"
  echo "  This can cause conflicts with the CVA6 installation."
  echo "  I will temporarily comment this line during installation."
  echo "  At the end, I will restore it and tell you to reload your terminal."
  while true; do
    read -p "Continue with installation? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      break
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
      echo "Installation cancelled by user."
      exit 1
    fi
    echo "Please answer 'y' or 'n'."
  done
  # Comment the line
  sed -i "${VIVADO_LINENUM}s/^/#/" "$HOME/.bashrc"
  echo "✓ Vivado settings line $VIVADO_LINENUM temporarily commented"
else
  echo "No Vivado settings found in ~/.bashrc - proceeding."
fi

# ============================================================
# CVA6 Installation Script
# ============================================================
# For known issues (especially on Kali Linux), see:
# README_KNOWN_ISSUES.md
# ============================================================
log_step() {
    echo ""
    echo -e "\033[36m==============================================\033[0m"
    echo -e "\033[36m  $1\033[0m"
    echo -e "\033[36m==============================================\033[0m"
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
    echo -e "\033[32m✓ All required system packages are already installed\033[0m"
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
  pkg-config libxml2-dev libxslt1-dev zlib1g-dev \
  libcairo2-dev libpango1.0-dev libpixman-1-dev \
  nodejs npm

# Install packages that may have issues on some distros (Kali, etc.)
echo ""
echo "Installing additional dependencies (may vary by distribution)..."

# Try libgdk-pixbuf2.0-dev first, fall back to libgdk-pixbuf-xlib-2.0-dev
if ! dpkg -s libgdk-pixbuf2.0-dev >/dev/null 2>&1; then
  if dpkg -s libgdk-pixbuf-xlib-2.0-dev >/dev/null 2>&1; then
    echo -e "\033[32m✓ Using libgdk-pixbuf-xlib-2.0-dev (replaces libgdk-pixbuf2.0-dev)\033[0m"
  else
    echo "Installing libgdk-pixbuf2.0-dev (or replacement)..."
    sudo apt install -y libgdk-pixbuf2.0-dev libgdk-pixbuf-xlib-2.0-dev 2>/dev/null || \
    sudo apt install -y libgdk-pixbuf-xlib-2.0-dev 2>/dev/null || \
    echo "WARNING: gdk-pixbuf development package installation failed. You may need to install manually."
  fi
fi

# Install libglib2.0-dev separately (may have issues on some distros like Kali)
if ! dpkg -s libglib2.0-dev >/dev/null 2>&1; then
  echo "Installing libglib2.0-dev (may have dependency issues on some distros)..."
  sudo apt install -y libglib2.0-dev || echo "WARNING: libglib2.0-dev installation failed. You may need to install it manually."
fi

# ------------------------------------------------------------
# Install documentation image generators (Node.js tools)
# ------------------------------------------------------------
if ! command -v bytefield-svg >/dev/null 2>&1; then
  echo "Installing bytefield-svg..."
  sudo npm install -g bytefield-svg
else
  echo -e "\033[32m✓ bytefield-svg is already installed\033[0m"
fi

if ! command -v wavedrom-cli >/dev/null 2>&1; then
  echo "Installing wavedrom-cli..."
  sudo npm install -g wavedrom-cli
else
  echo -e "\033[32m✓ wavedrom-cli is already installed\033[0m"
fi

# ============================================================
# Ruby gems (docs)
# ============================================================
if ask_yes_no "Install documentation tools (Ruby + Asciidoctor)?"; then
  echo "Installing Ruby gems for documentation..."
  
  # Install core gems first
  sudo gem install \
    asciidoctor \
    asciidoctor-bibtex \
    asciidoctor-diagram \
    asciidoctor-lists \
    pygments.rb
  
  # Install asciidoctor-mathematical separately (may have issues on some distros)
  echo "Installing asciidoctor-mathematical (may fail on some systems)..."
  sudo gem install asciidoctor-mathematical || echo "WARNING: asciidoctor-mathematical installation failed."
  echo -e "\033[32m✓ Ruby gems installed\033[0m"
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
# Python virtual environment setup (automatic)
# ============================================================
USE_PYTHON=false
VENV_PATH="$HOME/.pyenv/versions/cva6"

if [[ -d "$VENV_PATH" ]]; then
  echo "Using existing Python venv at $VENV_PATH..."
  USE_PYTHON=true
elif command -v python3 &> /dev/null; then
  echo "Creating Python venv at $VENV_PATH..."
  mkdir -p "$HOME/.pyenv/versions"
  python3 -m venv "$VENV_PATH"
  USE_PYTHON=true
fi

if $USE_PYTHON; then
  echo "Activating Python venv..."
  export VIRTUAL_ENV="$VENV_PATH"
  export PATH="$VIRTUAL_ENV/bin:$PATH"
  echo -e "\033[32m✓ Python virtual environment activated\033[0m"
fi

# ============================================================
# Git + toolchain
# ============================================================
log_step "Building RISC-V toolchain (GCC)"
cd "$CVA6_REPO"
echo "Initializing git submodules..."
git submodule update --init --recursive

# ------------------------------------------------------------
# Fix yaml-cpp compilation error (missing #include <cstdint>)
# ------------------------------------------------------------
YAML_CPP_FILE="$CVA6_REPO/verif/core-v-verif/vendor/riscv/riscv-isa-sim/yaml-cpp/src/emitterutils.cpp"
if [[ -f "$YAML_CPP_FILE" ]]; then
  if ! grep -q '#include <cstdint>' "$YAML_CPP_FILE"; then
    echo "Fixing yaml-cpp compilation error (missing #include <cstdint>)..."
    sed -i '12a #include <cstdint>' "$YAML_CPP_FILE"
    echo -e "\033[32m✓ yaml-cpp patch applied\033[0m"
  else
    echo -e "\033[32m✓ yaml-cpp already patched\033[0m"
  fi
fi

echo "Fetching toolchain sources..."
bash util/toolchain-builder/get-toolchain.sh

echo "Applying CVA6 GCC patch..."
cd util/toolchain-builder/src/gcc
git apply ../../gcc-cva6-tune.patch || echo "Patch already applied or not found"

echo "Building toolchain..."
cd "$CVA6_REPO/util/toolchain-builder"
bash build-toolchain.sh "$CONFIG_NAME" "$INSTALL_DIR"

# ============================================================
# Verify RISCV toolchain installation
# ============================================================
echo ""
echo "Verifying RISCV toolchain installation..."

# Check if RISCV toolchain was built successfully
if [[ -f "$RISCV/bin/riscv-none-elf-gcc" ]]; then
  echo -e "\033[32m✓ RISCV toolchain found at $RISCV\033[0m"
  
  # Verify basic compilation works
  echo "Testing RISCV toolchain..."
  TEST_FILE=$(mktemp)
  echo "int main() { return 0; }" > "$TEST_FILE.c"
  
  if "$RISCV/bin/riscv-none-elf-gcc" -o "$TEST_FILE" "$TEST_FILE.c" 2>/dev/null; then
    echo -e "\033[32m✓ RISCV toolchain basic compilation test passed\033[0m"
    rm -f "$TEST_FILE" "$TEST_FILE.c"
  else
    echo "WARNING: RISCV toolchain compilation test failed"
    rm -f "$TEST_FILE" "$TEST_FILE.c"
    echo ""
    echo "ERROR: RISCV toolchain may be incomplete or misconfigured."
    echo "This is likely due to missing newlib headers or incorrect configuration."
    echo "Please rebuild the toolchain or check the CVA6 repository for issues."
    echo ""
    echo "Common solutions:"
    echo "  1. Re-run the toolchain builder"
    echo "  2. Check if CONFIG_NAME matches your target (cv32a60x vs cv64a6_imafdc_sv39)"
    echo "  3. Verify the gcc-cva6-tune.patch was applied correctly"
  fi
  
  # Test if toolchain supports required extensions
  echo ""
  echo "Testing RISCV toolchain extension support..."
  TEST_FILE=$(mktemp)
  echo "int main() { return 0; }" > "$TEST_FILE.c"
  
  if "$RISCV/bin/riscv-none-elf-gcc" -march=rv32imc_zba_zbb_zbs_zbc_zicsr_zifencei -mabi=ilp32 -o "$TEST_FILE" "$TEST_FILE.c" 2>/dev/null; then
    echo -e "\033[32m✓ RISCV toolchain supports rv32imc_zba_zbb_zbs_zbc_zicsr_zifencei extensions\033[0m"
    TOOLCHAIN_EXTENSIONS_SUPPORTED=true
  else
    echo "WARNING: RISCV toolchain does NOT support rv32imc_zba_zbb_zbs_zbc_zicsr_zifencei extensions"
    echo ""
    echo "This means the toolchain was built without these extensions."
    echo "Simulations may fail with 'invalid -march= option' errors."
    TOOLCHAIN_EXTENSIONS_SUPPORTED=false
    
    # Try basic RV32IMC
    if "$RISCV/bin/riscv-none-elf-gcc" -march=rv32imc -mabi=ilp32 -o "$TEST_FILE" "$TEST_FILE.c" 2>/dev/null; then
      echo ""
      echo "Toolchain supports basic rv32imc. You can use this as a fallback."
      echo "To enable basic mode, export ENABLE_BASIC_EXTENSIONS=1 before running simulations."
      export ENABLE_BASIC_EXTENSIONS=1
    fi
  fi
  rm -f "$TEST_FILE" "$TEST_FILE.c"
else
  echo "ERROR: RISCV toolchain not found at $RISCV"
  echo "Toolchain build may have failed. Please check the build logs."
fi

# ============================================================
# Python requirements
# ============================================================
log_step "Installing Python requirements"
if $USE_PYTHON; then
  echo "Installing Python requirements..."
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
log_step "Building documentation"
if ask_yes_no "Build documentation now?"; then
  cd "$CVA6_REPO/docs"
  make
  echo -e "\033[32m✓ Documentation built successfully\033[0m"
fi

# ------------------------------------------------------------
# Configuration-specific manuals (optional)
# ------------------------------------------------------------
if ask_yes_no "Build configuration-specific manuals?"; then
  cd "$CVA6_REPO/docs"
  
  # Instruction set manuals (privileged & unprivileged)
  echo "Building instruction set manuals..."
  make -C 04_cv32a65x/riscv priv-html unpriv-html 2>/dev/null || echo "Warning: Could not build riscv manuals"
  
  # Design documentation
  echo "Building design documentation..."
  make -C 04_cv32a65x/design design-html 2>/dev/null || echo "Warning: Could not build design docs"
  
  echo -e "\033[32m✓ Configuration-specific manuals built\033[0m"
fi

# ============================================================
# Install Verilator and Spike using CVA6 official scripts
# ============================================================
log_step "Installing Verilator and Spike"
cd "$CVA6_REPO"

# Install Verilator (uses v5.008 with required patch for CVA6)
echo "Installing Verilator..."
bash verif/regress/install-verilator.sh

# Fix: Copy Verilator headers to include/ directory (install script doesn't do this correctly)
echo "Fixing Verilator headers..."
mkdir -p "$CVA6_REPO/tools/verilator-v5.008/include"
cp -r "$CVA6_REPO/tools/verilator-v5.008/build-v5.008/include/"* "$CVA6_REPO/tools/verilator-v5.008/include/" 2>/dev/null || true
cp -r "$CVA6_REPO/tools/verilator-v5.008/share/verilator/include/"* "$CVA6_REPO/tools/verilator-v5.008/include/" 2>/dev/null || true
echo -e "\033[32m✓ Verilator headers fixed\033[0m"

# Create symlink for DPI headers (Spike expects headers in include/vltstd/)
if [[ -d "$CVA6_REPO/tools/verilator-v5.008/share/verilator/include/vltstd" ]]; then
  if [[ ! -d "$CVA6_REPO/tools/verilator-v5.008/include/vltstd" ]]; then
    echo "Creating DPI headers directory..."
    mkdir -p "$CVA6_REPO/tools/verilator-v5.008/include"
    echo "Creating symlink for DPI headers..."
    ln -s "$CVA6_REPO/tools/verilator-v5.008/share/verilator/include/vltstd" "$CVA6_REPO/tools/verilator-v5.008/include/vltstd"
    echo -e "\033[32m✓ DPI headers symlink created\033[0m"
  else
    echo -e "\033[32m✓ DPI headers already available\033[0m"
  fi
  
  # Also create symlink in CVA6 repo root for Spike build system
  if [[ ! -d "$CVA6_REPO/include/vltstd" ]]; then
    echo "Creating DPI headers symlink in CVA6 repo root..."
    mkdir -p "$CVA6_REPO/include"
    ln -sf /Tools/cva6/tools/verilator-v5.008/share/verilator/include/vltstd "$CVA6_REPO/include/vltstd"
    echo -e "\033[32m✓ DPI headers symlink in repo root created\033[0m"
  fi
fi

# Set Verilator environment variables BEFORE installing Spike
export VERILATOR_INSTALL_DIR="$CVA6_REPO/tools/verilator-v5.008"
export VERILATOR_ROOT="$VERILATOR_INSTALL_DIR"

# Install Spike (uses vendorized version in CVA6 repo)
echo "Installing Spike..."
bash verif/regress/install-spike.sh

# Get the actual installation paths
SPIKE_INSTALL_DIR="$CVA6_REPO/tools/spike"

# Verify installations
if [[ -f "$VERILATOR_INSTALL_DIR/bin/verilator" ]]; then
  VERILATOR_VERSION=$("$VERILATOR_INSTALL_DIR/bin/verilator" --version 2>&1 || echo "unknown")
  echo -e "\033[32m✓ Verilator installed: $VERILATOR_VERSION\033[0m"
else
  echo "WARNING: Verilator installation may have failed"
fi

if [[ -f "$SPIKE_INSTALL_DIR/bin/spike" ]]; then
  SPIKE_VERSION=$("$SPIKE_INSTALL_DIR/bin/spike" --version 2>&1 || echo "unknown")
  echo -e "\033[32m✓ Spike installed: $SPIKE_VERSION\033[0m"
else
  echo "WARNING: Spike installation may have failed"
fi

# ============================================================
# Smoke tests
# ============================================================
log_step "Running smoke tests"

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
  echo -e "\033[32m✓ setup-env.sh sourced\033[0m"
fi

if ask_yes_no "Run smoke tests now?"; then
  echo "Running smoke tests..."
  cd "$CVA6_REPO"
  
  # Check if VCS is available, otherwise use Verilator
  if command -v vcs &> /dev/null; then
    echo "Using VCS simulator..."
    bash verif/regress/smoke-gen_tests.sh
  elif command -v verilator &> /dev/null; then
    echo "VCS not found, using Verilator instead..."
    export DV_SIMULATORS=veri-testharness
    bash verif/regress/smoke-gen_tests.sh
  else
    echo "ERROR: Neither VCS nor Verilator is installed. Skipping smoke tests."
    echo "  Install Verilator: apt-get install verilator"
  fi
  
  echo -e "\033[32m✓ Smoke tests completed\033[0m"
else
  echo "Skipping smoke tests."
fi

# ============================================================
# Standalone Simulations (examples)
# ============================================================
log_step "Running standalone simulations"

echo ""
echo "======================================"
echo "Running Standalone Simulations"
echo "======================================"

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
  export DV_SIMULATORS=veri-testharness
  
  # Check if toolchain supports required extensions
  MARCH_FLAGS="-march=rv32imc_zba_zbb_zbs_zbc_zicsr_zifencei"
  if [[ "${TOOLCHAIN_EXTENSIONS_SUPPORTED:-false}" == "false" ]]; then
    echo "WARNING: Toolchain doesn't support extended extensions. Using basic rv32imc."
    MARCH_FLAGS="-march=rv32imc"
  fi
  
  cd ./verif/sim
  python3 cva6.py --target cv32a60x --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml \
    --c_tests ../tests/custom/hello_world/hello_world.c \
    --linker=../../config/gen_from_riscv_config/linker/link.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -nostdlib \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S -lgcc \
    -I../tests/custom/env -I../tests/custom/common $MARCH_FLAGS -mabi=ilp32"
  cd "$CVA6_REPO"
  echo -e "\033[32m✓ hello_world simulation completed\033[0m"
fi

# RISC-V Proxy Kernel simulation (for printf support)
if ask_yes_no "Run veri-testharness-pk simulation?"; then
  export DV_SIMULATORS=veri-testharness-pk
  bash verif/regress/veri-testharness-pk-tests.sh
  echo -e "\033[32m✓ veri-testharness-pk simulation completed\033[0m"
fi

# VCS with Verdi
if ask_yes_no "Enable Verdi for VCS simulations?"; then
  export VERDI=1
  echo -e "\033[32m✓ VERDI=1 enabled (for VCS simulations)\033[0m"
fi

# Regression tests
if ask_yes_no "Run riscv-arch-test regression suite?"; then
  export DV_SIMULATORS=veri-testharness,spike
  bash verif/regress/dv-riscv-arch-test.sh
  echo -e "\033[32m✓ riscv-arch-test regression completed\033[0m"
fi

# Waveform generation for cv32a65x
if ask_yes_no "Generate waveforms for cv32a65x (TRACE_FAST)?"; then
  export DV_SIMULATORS=veri-testharness
  export DV_TARGET=cv32a65x
  export TRACE_FAST=1
  cd ./verif/sim
  python3 cva6.py --target cv32a60x --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml \
    --c_tests ../tests/custom/hello_world/hello_world.c \
    --linker=../../config/gen_from_riscv_config/linker/link.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -nostdlib \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S -lgcc \
    -I../tests/custom/env -I../tests/custom/common -march=rv32imc -mabi=ilp32"
  cd "$CVA6_REPO"
  echo -e "\033[32m✓ cv32a65x waveform generation configured\033[0m"
  echo "  Run manually: cd verif/sim && bash smoke-tests-cv32a65x.sh"
fi

# Waveform generation for cv32a6_imac_sv32
if ask_yes_no "Generate waveforms for cv32a6_imac_sv32 (TRACE_FAST)?"; then
  export DV_SIMULATORS=veri-testharness
  export DV_TARGET=cv32a6_imac_sv32
  export TRACE_FAST=1
  cd ./verif/sim
  python3 cva6.py --target cv32a6_imac --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml \
    --c_tests ../tests/custom/hello_world/hello_world.c \
    --linker=../../config/gen_from_riscv_config/linker/link.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -nostdlib \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S -lgcc \
    -I../tests/custom/env -I../tests/custom/common -march=rv32imac -mabi=ilp32"
  cd "$CVA6_REPO"
  echo -e "\033[32m✓ cv32a6_imac_sv32 waveform generation configured\033[0m"
  echo "  Run manually: cd verif/sim && bash smoke-tests-cv32a6_imac_sv32.sh"
fi

# Waveform generation for cv64a6_imafdc_sv39
if ask_yes_no "Generate waveforms for cv64a6_imafdc_sv39 (TRACE_FAST)?"; then
  export DV_SIMULATORS=veri-testharness,spike
  export DV_TARGET=cv64a6_imafdc_sv39
  export TRACE_FAST=1
  echo -e "\033[32m✓ cv64a6_imafdc_sv39 waveform generation configured\033[0m"
  echo "  Run manually: cd verif/sim && bash smoke-tests-cv64a6_imafdc_sv39.sh"
  echo "  Waveforms: ./verif/sim/out_YEAR-MONTH-DAY/*.vcd or *.fst"
fi

# Coverage and Verification Plan (VCS only)
if ask_yes_no "Enable coverage for VCS simulations?"; then
  export cov=1
  echo -e "\033[32m✓ Coverage enabled (cov=1)\033[0m"
fi

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
# Restore Vivado settings (uncomment at the end)
# ============================================================
VIVADO_LINE_COMMENTED=$(grep -n "^#.*source.*settings64" "$HOME/.bashrc" 2>/dev/null | head -1 || true)
if [[ -n "$VIVADO_LINE_COMMENTED" ]]; then
  VIVADO_LINENUM=$(echo "$VIVADO_LINE_COMMENTED" | cut -d: -f1)
  sed -i "${VIVADO_LINENUM}s/^#//" "$HOME/.bashrc"
  echo "NOTICE: Vivado settings line uncommented in ~/.bashrc"
  echo "  (Line $VIVADO_LINENUM restored)"
  echo "  Please reload your terminal: source ~/.bashrc"
fi

# ============================================================
# Environment persistence
# ============================================================
if ask_yes_no "Add CVA6, RISCV, Verilator, and Spike to ~/.bashrc?"; then
  if ! grep -q "CVA6 Environment" "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" << EOF

# ---- CVA6 Environment ----

export PATH="~/.pyenv/bin:\$PATH"
export PATH="~/.pyenv/shims:\$PATH"

export CVA6_REPO_DIR="$CVA6_REPO"
export VERILATOR_ROOT="$VERILATOR_INSTALL_DIR"
export VERILATOR_INSTALL_DIR="$VERILATOR_INSTALL_DIR"
export SPIKE_ROOT="$SPIKE_INSTALL_DIR"
export SPIKE_SRC_DIR="$CVA6_REPO/verif/core-v-verif/vendor/riscv/riscv-isa-sim"
export SPIKE_INSTALL_DIR="$SPIKE_INSTALL_DIR"
export RISCV="$RISCV"
export INSTALL_DIR="$RISCV"

# Set default variables to avoid unbound variable errors
export LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:-}"

# Add all tool paths to PATH
export PATH="$VERILATOR_INSTALL_DIR/bin:$SPIKE_INSTALL_DIR/bin:$RISCV/bin:\$PATH"

# Default simulation settings
export DV_SIMULATORS=veri-testharness,spike
export DV_TARGET=cv64a6_imafdc_sv39
export DV_TESTLISTS="../tests/testlist_riscv-tests-$DV_TARGET-p.yaml ../tests/testlist_riscv-tests-$DV_TARGET-v.yaml"
EOF
    echo -e "\033[32m✓ CVA6 environment added to ~/.bashrc\033[0m"
  else
    echo -e "\033[32m✓ CVA6 environment already present in ~/.bashrc\033[0m"
  fi
fi

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
echo ""
echo "Toolchain config : $CONFIG_NAME"
echo "RISCV path       : $RISCV"
echo ""
if $USE_PYTHON; then
  echo "To activate Python venv:"
  echo "  pyenv activate cva6"
  echo ""
fi
echo "To set environment for future sessions:"
echo "  The environment is already configured in ~/.bashrc"
echo ""
echo "======================================"
echo "UNINSTALL INSTRUCTIONS:"
echo "======================================"
echo ""
echo "To uninstall CVA6, run:"
echo "  bash $(dirname "$0")/cva6Uninstall.sh"
echo ""
echo "Or manually remove:"
echo "  rm -rf $CVA6_REPO"
echo "  rm -rf $RISCV"
echo "  rm -rf $CVA6_REPO/tools/verilator-v5.008"
echo "  rm -rf $CVA6_REPO/tools/spike"
echo "  pyenv uninstall cva6 2>/dev/null || true"
echo "  rm -rf ~/.pyenv/versions/cva6 2>/dev/null || true"
echo "  # Remove CVA6 Environment block from ~/.bashrc"
echo "======================================"
