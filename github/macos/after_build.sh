#!/bin/bash
set -ev

# Version from CI, fallback for local runs
: "${GC_VERSION:=3.8}"
cd src
export PIP_BREAK_SYSTEM_PACKAGES=1

# Setup variables
# GHA uses setup-python. We need to dynamicall find the paths.
PYTHON_FULL_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_BIN_PATH=$(which python3)
PYTHON_PREFIX=$(python3-config --prefix)

echo "Python Version: $PYTHON_FULL_VER"
echo "Python Prefix: $PYTHON_PREFIX"

# Define variables expected by the AppVeyor logic adaptation
# In AppVeyor, BREW_PYTHON_ROOT was the prefix.
BREW_PYTHON_ROOT="$PYTHON_PREFIX"

# Check if it is a Framework build (typical for macOS python)
if [[ "$PYTHON_PREFIX" == *".framework"* ]]; then
    # e.g. /opt/hostedtoolcache/.../Python.framework/Versions/3.11
    # We want .../Python.framework
    BREW_PYTHON_FRAMEWORK="${PYTHON_PREFIX%/Versions/*}"
else
    echo "ERROR: Python does not appear to be a Framework build. Bundling logic requires a Framework."
    # Fallback or exit? setup-python on macOS normally provides a framework.
    exit 1
fi

echo "Python Framework Root: $BREW_PYTHON_FRAMEWORK"

echo "About to create dmg file and fix up"
mkdir -p GoldenCheetah.app/Contents/Frameworks

# Copy libicudata
# First try brew icu4c (common dependency)
BREW_PREFIX=$(brew --prefix)
if [ -d "$BREW_PREFIX/opt/icu4c/lib" ]; then
    find "$BREW_PREFIX/opt/icu4c/lib" -name "libicudata.*.dylib" -exec cp {} GoldenCheetah.app/Contents/Frameworks \;
fi

# Copy python framework
echo "Copying Python Framework from ${BREW_PYTHON_FRAMEWORK}"
# Remove any old attempts
rm -rf GoldenCheetah.app/Contents/Frameworks/Python.framework
mkdir -p GoldenCheetah.app/Contents/Frameworks/Python.framework
# We copy the whole framework
rsync -axL --exclude='Tk.framework' --exclude='Tcl.framework' --exclude='PrivateHeaders' "$BREW_PYTHON_FRAMEWORK/" "GoldenCheetah.app/Contents/Frameworks/Python.framework/"

# Ensure write permissions
chmod -R +w GoldenCheetah.app/Contents/Frameworks

# Clean up other versions if present in the copy (keep only current)
# This reduces bundle size.
pushd GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions
ls | grep -v "$PYTHON_FULL_VER" | xargs rm -rf
popd

# 2. Install Python Requirements & Fix Framework
# Consolidated into shared script
echo "Calling shared Python install script..."
bash ../github/macos/install_python_deps.sh "GoldenCheetah.app" "${PYTHON_FULL_VER}" "../src/Python/requirements.txt"

# 3. Qt Deployment
# 3. Qt Deployment
echo "Calling shared Qt packaging script..."
bash ../github/macos/package_qt.sh "GoldenCheetah.app"


# Using shared signing script
echo "Calling shared signing script..."
bash ../github/macos/sign_bundle.sh "GoldenCheetah.app" "${PYTHON_FULL_VER}"

echo "Creating DMG..."
hdiutil create -volname GoldenCheetah -srcfolder GoldenCheetah.app -ov -format UDZO GoldenCheetah.dmg
mv GoldenCheetah.dmg "../GoldenCheetah_v${GC_VERSION}_x64.dmg"



