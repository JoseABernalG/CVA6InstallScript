#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# Helpers
# -------------------------
expand_path() {
  local path="$1"
  if [[ "$path" == "~"* ]]; then
    echo "${path/#\~/$HOME}"
  else
    echo "$path"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# -------------------------
# Ask for locations
# -------------------------
read -p "Enter CVA6 repo path (e.g., ~/cva6): " CVA6_REPO
read -p "Enter RISCV install path (e.g., ~/riscv): " RISCV

CVA6_REPO=$(expand_path "$CVA6_REPO")
RISCV=$(expand_path "$RISCV")

CVA6_REPO=$(realpath "$CVA6_REPO")
RISCV=$(realpath "$RISCV")

if [[ ! -d "$CVA6_REPO" ]]; then
  echo "ERROR: CVA6 repo not found at $CVA6_REPO"
  exit 1
fi

mkdir -p "$RISCV"

export RISCV
export INSTALL_DIR="$RISCV"

# -------------------------
# Load pyenv for script
# -------------------------
export PATH="$HOME/.cva/bin/:$PATH"
export PATH="$HOME/.cva/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# -------------------------
# Create/activate virtualenv cva6
# -------------------------
if pyenv versions --bare | grep -q "^cva6\$"; then
  echo "Virtualenv 'cva6' already exists. Activating..."
else
  echo "Creating pyenv virtualenv 'cva6'..."
  pyenv install -s 3.12.2
  pyenv virtualenv 3.12.2 cva6
fi

pyenv activate cva6

# -------------------------
# Add pyenv init to .bashrc if missing
# -------------------------
BASHRC="$HOME/.bashrc"
if ! grep -q "pyenv virtualenv-init" "$BASHRC"; then
  cat >> "$BASHRC" << 'EOF'

# ---- CVA6 environment setup ----
export PATH="$HOME/.cva/bin/:$PATH"
export PATH="$HOME/.cva/shims:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOF
fi

# -------------------------
# Threads
# -------------------------
read -p "Use all available threads? (y/n): " opti
case "$opti" in
    y|Y) NUM_JOBS=$(nproc) ;;
    n|N) read -p "Enter number of threads: " NUM_JOBS ;;
    *) echo "Not valid answer."; exit 1 ;;
esac
export NUM_JOBS
echo "Using $NUM_JOBS threads"

# -------------------------
# Install prerequisites
# -------------------------
sudo apt-get update
sudo apt-get install -y \
    autoconf automake autotools-dev curl git \
    libmpc-dev libmpfr-dev libgmp-dev gawk \
    build-essential bison flex texinfo gperf \
    libtool bc zlib1g-dev help2man device-tree-compiler \
    python3 python3-pip python3-venv \
    ruby ruby-dev build-essential

# -------------------------
# Config name (based on installed GCC)
# -------------------------
GCC_VER=$(gcc -dumpversion 2>/dev/null || echo "13.3.0")
CONFIG_NAME="gcc-${GCC_VER}-BareMetal"

read -p "Custom config name? (y/n) [default: $CONFIG_NAME]: " opti
case "$opti" in
    y|Y)
        read -p "Enter custom config name: " CONFIG_NAME
        ;;
    n|N|"")
        ;;
    *)
        echo "Not valid answer."
        exit 1
        ;;
esac

export CONFIG_NAME
echo "Using config: $CONFIG_NAME"

# -------------------------
# Git submodule update
# -------------------------
cd "$CVA6_REPO"
git submodule update --init --recursive

# -------------------------
# Fetch toolchain
# -------------------------
echo "Fetching toolchain sources..."
bash "$CVA6_REPO/util/toolchain-builder/get-toolchain.sh"

# -------------------------
# Apply patch
# -------------------------
echo "Applying CVA6 GCC patch..."
cd "$CVA6_REPO/util/toolchain-builder/src/gcc"
git apply ../../gcc-cva6-tune.patch

# -------------------------
# Build toolchain
# -------------------------
echo "Building toolchain..."
cd "$CVA6_REPO/util/toolchain-builder"
bash build-toolchain.sh "$CONFIG_NAME" "$INSTALL_DIR"

# -------------------------
# Install Python requirements
# -------------------------
pip3 install -r "$CVA6_REPO/verif/sim/dv/requirements.txt"

# -------------------------
# Install Ruby gems for docs (with sudo)
# -------------------------
echo "Installing Ruby gems (requires sudo)..."
sudo gem install asciidoctor asciidoctor-bibtex asciidoctor-diagram asciidoctor-lists asciidoctor-mathematical pygments.rb

# -------------------------
# Run smoke tests
# -------------------------
read -p "Run CVA6 smoke tests now? (y/n): " opti
if [[ "$opti" == "y" || "$opti" == "Y" ]]; then
    export DV_SIMULATORS=veri-testharness,spike
    bash "$CVA6_REPO/verif/regress/smoke-tests-cv32a65x.sh"
fi

# -------------------------
# Documentation option
# -------------------------
read -p "Build documentation now? (y/n): " opti
if [[ "$opti" == "y" || "$opti" == "Y" ]]; then
    cd "$CVA6_REPO/docs"
    make
else
    echo ""
    echo "To build docs later:"
    echo "  pyenv activate cva6"
    echo "  cd $CVA6_REPO/docs"
    echo "  make"
fi

# -------------------------
# Final message
# -------------------------
echo "======================================"
echo "Installation complete."
echo ""
echo "Activate env:"
echo "  pyenv activate cva6"
echo "Deactivate env:"
echo "  pyenv deactivate"
echo "======================================"




# Example commands to build docs:



#exit 0
#make -C 04_cv32a65x/design design-html

#rm -Rf cva6 RISCV && mkdir RISCV
#git clone https://github.com/openhwgroup/cva6.git
#./CVA6InstallScript/cva6Install.sh
