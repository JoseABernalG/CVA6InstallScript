#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Global vars
# ============================================================

VERILATOR_INCLUDE=""
CONFIG_NAME=""

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

# ============================================================
# Environment initializer (robust)
# ============================================================

init_environment() {
    echo "Initializing environment..."

    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"

    if [[ -z "${CV_SW_PREFIX:-}" ]]; then
        export CV_SW_PREFIX="riscv64-unknown-elf-"
    fi

    if [[ -z "${RISCV_CC:-}" ]]; then
        export RISCV_CC="$RISCV/bin/${CV_SW_PREFIX}gcc"
    fi

    if [[ -z "${RISCV_OBJCOPY:-}" ]]; then
        export RISCV_OBJCOPY="$RISCV/bin/${CV_SW_PREFIX}objcopy"
    fi

    # Detect Verilator headers
    if [[ -z "${VERILATOR_INCLUDE:-}" ]]; then
        VERILATOR_INCLUDE=$(find "$CVA6_REPO/tools" \
            -type f -name vpi_user.h 2>/dev/null | head -n1 || true)

        if [[ -n "$VERILATOR_INCLUDE" ]]; then
            VERILATOR_INCLUDE=$(dirname "$VERILATOR_INCLUDE")
        fi
    fi

    if [[ -n "${VERILATOR_INCLUDE:-}" ]]; then
        export C_INCLUDE_PATH="$VERILATOR_INCLUDE${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
        export CPLUS_INCLUDE_PATH="$VERILATOR_INCLUDE${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
    fi
}

# ============================================================
# Ask toolchain config
# ============================================================

ask_toolchain_config() {

    if [[ -z "${CONFIG_NAME:-}" ]]; then
        CONFIG_DIR="$CVA6_REPO/util/toolchain-builder/config"

        echo ""
        echo "Available toolchain configs:"

        mapfile -t CONFIGS < <(ls "$CONFIG_DIR"/*.sh \
            | xargs -n1 basename \
            | sed 's/.sh$//' \
            | sort)

        for i in "${!CONFIGS[@]}"; do
            echo "$((i+1))) ${CONFIGS[$i]}"
        done

        echo ""
        read -p "Select config number or enter custom name: " sel

        if [[ "$sel" =~ ^[0-9]+$ ]] && \
           (( sel>=1 && sel<=${#CONFIGS[@]} )); then
            CONFIG_NAME="${CONFIGS[$((sel-1))]}"
        else
            CONFIG_NAME="$sel"
        fi

        export CONFIG_NAME
    fi
}

# ============================================================
# Paths
# ============================================================

DEFAULT_CVA6_REPO="$HOME/cva6"
DEFAULT_RISCV="$HOME/riscv"

read -p "Enter CVA6 repo path [${DEFAULT_CVA6_REPO}]: " CVA6_REPO
read -p "Enter RISCV install path [${DEFAULT_RISCV}]: " RISCV

CVA6_REPO=${CVA6_REPO:-$DEFAULT_CVA6_REPO}
RISCV=${RISCV:-$DEFAULT_RISCV}

CVA6_REPO=$(realpath "$(expand_path "$CVA6_REPO")")
RISCV=$(realpath "$(expand_path "$RISCV")")

[[ ! -d "$CVA6_REPO" ]] && echo "ERROR: repo not found" && exit 1
mkdir -p "$RISCV"

export RISCV
export INSTALL_DIR="$RISCV"

# ============================================================
# Threads
# ============================================================

echo ""
read -p "Use all available threads? (y/n): " opti
case "$opti" in
  y|Y) NUM_JOBS=$(nproc) ;;
  n|N) read -p "Threads: " NUM_JOBS ;;
  *) echo "Invalid"; exit 1 ;;
esac

export NUM_JOBS
echo "Using $NUM_JOBS threads"

# ============================================================
# Menu Loop
# ============================================================

while true; do

echo ""
echo "Select steps:"
echo "1) Fix machine.adoc"
echo "2) Update submodules"
echo "3) Build toolchain"
echo "4) Install/verify Verilator"
echo "5) Install/verify Spike"
echo "6) Run smoke tests"
echo "7) Build documentation"
echo "8) Add RISCV to ~/.bashrc"
echo "0) Exit"

read -p "Choice: " choices
IFS=',' read -ra CHOICES <<< "$choices"

for choice in "${CHOICES[@]}"; do
case $choice in

0)
  echo "Exiting installer."
  exit 0
  ;;

1)
  echo "Fixing documentation..."
  MACHINE_ADOC="$CVA6_REPO/docs/riscv-isa/src/machine.adoc"

  if [[ -f "$MACHINE_ADOC" ]]; then
      echo "Checking endif::[] near line 3114..."

      # Verifica si ya existe en el rango cercano
      if sed -n '3105,3125p' "$MACHINE_ADOC" | grep -q 'endif::\[\]'; then
          echo "Documentation already patched."
      else
          echo "Inserting endif::[] at line 3114..."
          sed -i '3114i endif::[]' "$MACHINE_ADOC"
          echo "Patch applied successfully."
      fi
  else
      echo "machine.adoc not found."
  fi
  ;;

2)
  cd "$CVA6_REPO"
  git submodule update --init --recursive
  ;;

3)
  echo "Building toolchain..."
  cd "$CVA6_REPO"

  ask_toolchain_config

  bash util/toolchain-builder/get-toolchain.sh "$CONFIG_NAME"

  cd util/toolchain-builder/src/gcc
  git apply ../../gcc-cva6-tune.patch || true

  cd "$CVA6_REPO/util/toolchain-builder"
  bash build-toolchain.sh "$CONFIG_NAME" "$INSTALL_DIR"
  ;;

4)
  cd "$CVA6_REPO"
  bash verif/regress/install-verilator.sh
  ;;

5)
  cd "$CVA6_REPO"
  bash verif/regress/install-spike.sh
  ;;

6)
  echo "Running smoke tests..."
  cd "$CVA6_REPO"

  init_environment
  source verif/sim/setup-env.sh

  bash verif/regress/smoke-gen_tests.sh
  ;;

7)
  cd "$CVA6_REPO/docs"
  make
  ;;

8)
cat >> "$HOME/.bashrc" << EOF

# ---- CVA6 toolchain ----
export RISCV="$RISCV"
export PATH="\$RISCV/bin:\$PATH"
EOF
echo "Added to ~/.bashrc"
  ;;

*)
  echo "Invalid option: $choice"
  ;;
esac
done

done
