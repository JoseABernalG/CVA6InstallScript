#!/bin/bash
##Script to install CVA6

read -p "Use all available threads? (y/n): " opti

case "$opti" in
    y|Y)
        # Use all available threads
        export NUM_JOBS=$(nproc)
        ;;
    n|N)
        # Use 8 threads
        read -p "Enter number of threads: " NUM_JOBS
        export NUM_JOBS
        ;;
    *)
        echo "Not valid answer."
        exit 1
        ;;
esac

echo "Using $NUM_JOBS threads"

#Install Prerequisites
echo -e "Installing prerequisites...\n"

sudo apt-get install autoconf
sudo apt-get install automake
sudo apt-get install autotools-dev
sudo apt-get install curl
sudo apt-get install git
sudo apt-get install libmpc-dev
sudo apt-get install libmpfr-dev
sudo apt-get install libgmp-dev
sudo apt-get install gawk
sudo apt-get install build-essential
sudo apt-get install bison
sudo apt-get install flex
sudo apt-get install texinfo
sudo apt-get install gperf
sudo apt-get install libtool
sudo apt-get install bc
sudo apt-get install zlib1g-dev


##Setting up environment variables
echo -e "Setting up environment variables\n"

echo -e "path to the cva6 installation directory\n"

echo -e "example: '/home/user/Documents/cva6' \n"

read ins

#echo $ins

export RISCV="$ins"w

#echo $RISCV

INSTALL_DIR="$RISCV"

#echo $INSTALL_DIR

echo -e "Do you want to set a custom config name? (y/n)\nDefault => gcc-13.3.0-BareMetal \n"
read opti

case "$opti" in
    y|Y)
        # Using custom name
        read -p "Enter custom config name: " cfgnm
        export CONFIG_NAME="$cfgnm"
        ;;
    n|N)
        # Use default config name
        echo -e "Using default \n "
        export CONFIG_NAME="gcc-13.3.0-BareMetal"
        ;;
    *)
        echo "Not valid answer."
        exit 1
        ;;
esac

echo -e "Using $CONFIG_NAME \n"

echo -e "INSTALL_DIR = $Config_NAME located in $RISCV \n"

##Fetch the source code of the toolchain (assumes Internet access.)
##bash get-toolchain.sh
echo -e "Fetching toolchain...\n"

bash "$INSTALL_DIR"/util/toolchain-builder/get-toolchain.sh

#echo -e "$INSTALL_DIR/util/toolchain-builder/get-toolchain.sh\n"

echo -e "Applying gcc-cva6-tune.patch to add support for the -mtune=cva6 option in GCC.\n"

#echo -e "cd $INSTALL_DIR/util/toolchain-builder/src/gcc && git apply ../../gcc-cva6-tune.patch\n" 

cd $INSTALL_DIR/util/toolchain-builder/src/gcc && git apply ../../gcc-cva6-tune.patch

echo -e "Building a bare metal toolchain\n"

bash build-toolchain.sh $CONFIG_NAME $INSTALL_DIR