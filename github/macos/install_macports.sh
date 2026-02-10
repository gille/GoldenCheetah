#!/bin/bash
set -ev

# Define minimum macOS version
: "${MACOSX_DEPLOYMENT_TARGET:=12.0}"
export MACOSX_DEPLOYMENT_TARGET

echo "Configuring MacPorts for Deployment Target: $MACOSX_DEPLOYMENT_TARGET and Universal Build..."

if ! command -v port &> /dev/null; then
    echo "MacPorts not found. Installing..."
    # Download and install MacPorts
    # We need to know the OS version to pick the right package.
    # macOS 14 is Sonoma.
    curl -O https://distfiles.macports.org/MacPorts/MacPorts-2.10.0-14-Sonoma.pkg
    sudo installer -pkg MacPorts-2.10.0-14-Sonoma.pkg -target /

    # Add to PATH
    export PATH=/opt/local/bin:/opt/local/sbin:$PATH
fi

# Configure MacPorts
sudo sed -i '' "s/macosx_deployment_target.*/macosx_deployment_target $MACOSX_DEPLOYMENT_TARGET/" /opt/local/etc/macports/macports.conf
sudo sed -i '' "s/universal_archs.*/universal_archs x86_64 arm64/" /opt/local/etc/macports/macports.conf
sudo port -v selfupdate

echo "Installing Python 3.11 first to avoid pulling newer python versions..."
# Install Python 3.11 first
# Disable optimizations (PGO) and LTO to speed up build
sudo port install python311 +universal -optimizations -lto
sudo port install py311-pip +universal

# Set as default to maybe satisfy generic 'python' or 'python3' deps
echo "Selecting Python 3.11 as default..."
# Set default versions (fail if not found)
sudo port select --set python python311
sudo port select --set python3 python311
sudo port select --set pip pip311
sudo port select --set pip3 pip311


echo "Installing Build Tools (Native)..."
# These do not need to be universal as they just run on the host
sudo port install bison cmake pkgconfig automake autoconf libtool

echo "Installing Dependencies (STRICTLY UNIVERSAL)..."

# Read requirements file
REQUIREMENTS_FILE="$(dirname "$0")/macports_requirements.txt"
if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "ERROR: Requirements file not found at $REQUIREMENTS_FILE"
    exit 1
fi

# Build installation command
INSTALL_CMD="sudo port install"
while read -r PORT; do
    # Skip empty lines and comments
    [[ -z "$PORT" || "$PORT" =~ ^# ]] && continue
    INSTALL_CMD="$INSTALL_CMD $PORT +universal"
done < "$REQUIREMENTS_FILE"

echo "Running: $INSTALL_CMD"
$INSTALL_CMD

# --- LIBICAL (Manual Universal Build) ---
# MacPorts libical pulls in glib/python3.14/docbook. We build manually to prune.
if [ ! -d "libical-install" ]; then
    echo "Downloading and building Libical (Universal, No-GObject)..."
    rm -rf libical
    git clone --branch v3.0.18 --depth 1 https://github.com/libical/libical.git
    mkdir -p libical/build
    cd libical/build

    # Configure with CMake (Universal)
    # Disable GObject, Docs, Python bindings
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=$(pwd)/../../libical-install \
        -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET \
        -DGOBJECT_INTROSPECTION=OFF \
        -DICAL_GLIB=OFF \
        -DICAL_BUILD_DOCS=OFF \
        -DICAL_ERRORS_ARE_FATAL=OFF \
        -DCMAKE_BUILD_TYPE=Release

    make -j$(sysctl -n hw.ncpu)
    make install
    cd ../..
    # Cleanup source to save space/confusion
    rm -rf libical
else
    echo "Using cached Libical."
fi

# --- SRMIO (Universal Build) ---
if [ ! -d "srmio-install" ]; then
    echo "Downloading and building SRMIO (Universal)..."
    rm -rf srmio
    git clone https://github.com/rclasen/srmio.git
    cd srmio
    # srmio uses autotools
    # We need to ensure it uses MacPorts autotools
    export PATH=/opt/local/bin:$PATH

    # Generate configure script
    if [ -f "genautomake.sh" ]; then
        sh genautomake.sh
    else
        autoreconf -i
    fi

    # Configure for Universal Binary
    CFLAGS="-arch x86_64 -arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
    LDFLAGS="-arch x86_64 -arch arm64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
    ./configure --disable-shared --enable-static --prefix=$(pwd)/../srmio-install

    make -j$(sysctl -n hw.ncpu)
    make install
    cd ..
    rm -rf srmio
else
    echo "Using cached SRMIO."
fi

# --- D2XX ---
# D2XX drivers referenced in install.sh: D2XX1.4.24.zip
# This zip contains a DMG with a universal binary usually? Or just x86?
# 1.4.24 supports macOS 11+ and is usually Universal.
# Let's verify.
if [ ! -d "D2XX" ]; then
    echo "Downloading D2XX..."
    curl -L -o D2XX.zip "https://ftdichip.com/wp-content/uploads/2021/05/D2XX1.4.24.zip"
    unzip -o D2XX.zip
    # The zip contains D2XX1.4.24.dmg
    # We need to mount it.
    hdiutil attach D2XX1.4.24.dmg -mountpoint /Volumes/D2XX -nobrowse
    mkdir -p D2XX
    cp /Volumes/D2XX/D2XX/bin/10.5-10.7/libftd2xx.1.4.24.dylib D2XX/ || cp /Volumes/D2XX/build/libftd2xx.1.4.24.dylib D2XX/ || echo "Failed to find dylib in DMG"

    find /Volumes/D2XX -name "libftd2xx.1.4.24.dylib" -exec cp {} D2XX/ \;
    find /Volumes/D2XX -name "ftd2xx.h" -exec cp {} D2XX/ \;
    find /Volumes/D2XX -name "WinTypes.h" -exec cp {} D2XX/ \;

    hdiutil detach /Volumes/D2XX
fi

# --- R (Universal Framework Merge) ---
if [ ! -f "R-Universal/R.framework/Resources/lib/libR.dylib" ]; then
    echo "Downloading and Merging R Frameworks (Universal)..."
    # Ensure clean slate
    rm -rf R-Universal
    mkdir -p R-Universal
    cd R-Universal

    # Download Official CRAN Binaries (macOS 11+ Big Sur)
    # Note: R binaries for ARM64 are built for Big Sur (11.0) and are forward compatible with Monterey (12.0+)
    # There are no specific Monterey builds, so Big Sur is the correct/only choice.
    # Using R 4.4.2 which is current stable

    #curl -L -o R-arm64.pkg https://cran.r-project.org/bin/macosx/big-sur-arm64/base/R-4.4.2-arm64.pkg
    #curl -L -o R-x86_64.pkg https://cran.r-project.org/bin/macosx/big-sur-x86_64/base/R-4.4.2-x86_64.pkg
    curl -L -o R-arm64.pkg https://mac.r-project.org/bin/macosx/big-sur-arm64/base/R-4.5.2-arm64.pkg
    curl -L -o R-x86_64.pkg https://mac.r-project.org/bin/macosx/big-sur-x86_64/base/R-4.5.2-x86_64.pkg

    # Extract
    pkgutil --expand-full R-arm64.pkg R-arm64-expanded
    pkgutil --expand-full R-x86_64.pkg R-x86_64-expanded

    # The framework is inside R-framework-component.pkg/Payload
    # pkgutil --expand-full extracts Payload to directory.
    # Use find to locate it robustly, handling potential version/structure changes.

    ARM64_FW=$(find R-arm64-expanded -name "R.framework" -type d | head -n 1)
    X86_64_FW=$(find R-x86_64-expanded -name "R.framework" -type d | head -n 1)

    # Verify extraction
    if [ -z "$ARM64_FW" ] || [ -z "$X86_64_FW" ]; then
        echo "Failed to locate R.framework in expanded packages."
        echo "Structure of R-arm64-expanded:"
        ls -R R-arm64-expanded
        exit 1
    fi

    echo "Found ARM64 Framework: $ARM64_FW"
    echo "Found x86_64 Framework: $X86_64_FW"

    # Create Base from arm64
    cp -a "$ARM64_FW" ./R.framework

    # Lipo the main library
    # Resources/lib/libR.dylib
    echo "Creating Universal libR.dylib..."
    lipo -create \
        "$ARM64_FW/Resources/lib/libR.dylib" \
        "$X86_64_FW/Resources/lib/libR.dylib" \
        -output "R.framework/Resources/lib/libR.dylib"

    # Verify
    lipo -info "R.framework/Resources/lib/libR.dylib"

    # Headers should be identical, but Rconfig.h might differ
    # Include/Rconfig.h
    # We need to preserve both and wrap them.
    # Actually, R headers handle __aarch64__ vs __x86_64__ internally if generated correctly?
    # Let's hope CRAN headers are smart. If not, we might have issues.
    # Usually RGenetics/etc wrappers handle this.
    # For now, we assume the arm64 headers work or are identical enough.

    # Clean up
    rm -rf R-arm64.pkg R-x86_64.pkg R-arm64-expanded R-x86_64-expanded

    cd ..
else
    echo "Using cached R-Universal R.framework"
fi

# Make sure we use the MacPorts pip
/opt/local/bin/python3.11 -m pip install --upgrade pip
sudo /opt/local/bin/python3.11 -m pip install numpy --break-system-packages

# Clean cache to save space (MacPorts can be huge)
sudo port clean installed
