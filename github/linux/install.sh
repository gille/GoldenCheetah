#!/bin/bash
set -ev

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libgl1-mesa-dev \
    libgsl-dev \
    libical-dev \
    libusb-1.0-0-dev \
    libsamplerate0-dev \
    libudev-dev \
    bison \
    flex \
    libssl-dev \
    automake \
    autoconf \
    libtool \
    libpulse-dev \
    libxcb-cursor-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libfuse2 \
    patchelf

# R configuration
# GHA Ubuntu images might have R, or we can install it.
# sudo apt-get install -y r-base
# AppVeyor installs R.
if ! command -v R &> /dev/null; then
    sudo apt-get install -y r-base
fi

# Python deps
python3 -m pip install --upgrade pip
python3 -m pip install --only-binary :all: -r src/Python/requirements.txt

# D2XX - refresh cache if folder is empty
if [ ! -d "D2XX" ] || [ -z "$(ls -A D2XX)" ]; then
    mkdir -p D2XX
    D2XX_URL="https://ftdichip.com/wp-content/uploads/2022/07/libftd2xx-x86_64-1.4.27.tgz"
    D2XX_FILE="libftd2xx-x86_64-1.4.27.tgz"

    # Retry loop
    for i in {1..5}; do
        echo "Attempt $i: Downloading D2XX..."
        if wget --no-verbose "$D2XX_URL" -O "$D2XX_FILE" && tar -tzf "$D2XX_FILE" > /dev/null 2>&1; then
            echo "Download and validation successful."
            break
        fi

        echo "Download or validation failed. Retrying in 5s..."
        rm -f "$D2XX_FILE"
        sleep 5
    done

    if [ ! -f "$D2XX_FILE" ]; then
        echo "Failed to download D2XX after 5 attempts."
        exit 1
    fi

    tar xf "$D2XX_FILE" -C D2XX
fi

# SRMIO
if [ ! -d "srmio" ]; then
    git clone https://github.com/rclasen/srmio.git
    cd srmio
    sh genautomake.sh
    ./configure --disable-shared --enable-static
    make --silent -j$(nproc)
    sudo make install
    cd ..
fi
