#!/bin/bash
set -ev

date

# Install dependencies via Homebrew
# Using 'bison' (latest) instead of old 'bison@2.7' if possible, or check if 2.7 is available.
# Homebrew removed bison@2.7 in 2024. using `bison` (latest)
# Helper to install if not present
brew_install() {
    if brew list "$1" >/dev/null 2>&1; then
        echo "$1 already installed"
    else
        brew install "$1"
    fi

}

# Retry download helper
download_file() {
    local url="$1"
    local filename="$2"
    local validation_cmd="$3"
    local retries=5
    local wait=5

    for ((i=1; i<=retries; i++)); do
        echo "Attempt $i of $retries to download $filename..."
        # curl -L -f -o is important to fail on HTTP errors
        if curl -L -f -o "$filename" "$url"; then
            if [ -n "$validation_cmd" ]; then
                if eval "$validation_cmd"; then
                    echo "Validation successful."
                    return 0
                else
                    echo "Validation failed."
                fi
            else
                echo "Download successful."
                return 0
            fi
        else
            echo "Download failed."
        fi
        
        rm -f "$filename"
        echo "Waiting ${wait}s..."
        sleep $wait
    done
    
    echo "Failed to download $filename"
    exit 1
}

brew_install bison
brew_install gsl
brew_install libical
brew_install libusb
brew_install libsamplerate
brew_install openssl@3
brew_install automake
brew_install autoconf
brew_install libtool

# Ensure brew tools are in PATH
# Sometimes brew installs keg-only or the path isn't refreshed
BREW_PREFIX=$(brew --prefix)
export PATH="$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/opt/automake/bin:$BREW_PREFIX/opt/autoconf/bin:$BREW_PREFIX/opt/libtool/bin:$PATH"

# R Framework
# Installing R from CRAN pkg as in AppVeyor
# R Framework
# Installing R from CRAN pkg as in AppVeyor
# Detect architecture for correct R package
ARCH=$(uname -m)
if [ "$ARCH" == "arm64" ]; then
    echo "Detected ARM64. Downloading R for Apple Silicon..."
    download_file "https://cran.r-project.org/bin/macosx/big-sur-arm64/base/R-4.1.1-arm64.pkg" "R-4.1.1-arm64.pkg" ""
    sudo installer -pkg R-4.1.1-arm64.pkg -target /
else
    echo "Detected x86_64. Downloading R for Intel..."
    download_file "https://cran.r-project.org/bin/macosx/base/R-4.1.1.pkg" "R-4.1.1.pkg" ""
    sudo installer -pkg R-4.1.1.pkg -target /
fi

# STMIO
if [ ! -d "srmio" ]; then
    git clone https://github.com/rclasen/srmio.git
    cd srmio
    sh genautomake.sh
    ./configure --disable-shared --enable-static
    make -j$(sysctl -n hw.ncpu) --silent
    sudo make install
    cd ..
fi

# D2XX
if [ ! -d "D2XX" ]; then
    mkdir -p D2XX
    mkdir -p D2XX
    download_file "https://ftdichip.com/wp-content/uploads/2021/05/D2XX1.4.24.zip" "D2XX1.4.24.zip" "unzip -t D2XX1.4.24.zip >/dev/null"
    unzip -o D2XX1.4.24.zip
    hdiutil mount D2XX1.4.24.dmg
    # Copy files
    cp /Volumes/dmg/release/build/libftd2xx.1.4.24.dylib D2XX
    cp /Volumes/dmg/release/build/libftd2xx.a D2XX
    cp /Volumes/dmg/release/*.h D2XX
    hdiutil detach /Volumes/dmg
fi

# Install D2XX to system lib for linking
# For ARM, this should go to /usr/local/lib or /opt/homebrew/lib?
# Start with /usr/local/lib which is standard for user-installed libs even on ARM, 
# although /opt/homebrew is for brew.
sudo mkdir -p /usr/local/lib
sudo cp D2XX/libftd2xx.1.4.24.dylib /usr/local/lib/
sudo ln -sf /usr/local/lib/libftd2xx.1.4.24.dylib /usr/local/lib/libftd2xx.dylib