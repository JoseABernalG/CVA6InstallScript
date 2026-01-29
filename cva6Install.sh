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
  texlive-latex-base texlive-latex-extra texlive-fonts-recommended

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

# ============================================================
# Smoke tests
# ============================================================
if ask_yes_no "Run smoke tests now?"; then
  echo "Running smoke tests from CVA6 repo root..."
  cd "$CVA6_REPO"

  $USE_PYTHON && source "$HOME/ScammaCVA6/bin/activate"

  export DV_SIMULATORS=veri-testharness,spike
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





# Example commands to build docs:



#exit 0
#make -C 04_cv32a65x/design design-html

#rm -Rf cva6 RISCV && mkdir RISCV
#git clone https://github.com/openhwgroup/cva6.git
#./CVA6InstallScript/cva6Install.sh
