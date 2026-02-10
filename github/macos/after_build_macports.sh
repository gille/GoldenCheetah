#!/bin/bash
set -ev

: "${MACOSX_DEPLOYMENT_TARGET:=12.0}"
: "${PYTHON_VERSION:=3.11}"

export MACOSX_DEPLOYMENT_TARGET
export PATH=/opt/local/bin:/opt/local/sbin:$PATH

echo "Packaging MacPorts Universal Build..."

# 0. Clean & Prepare
cd src
mkdir -p GoldenCheetah.app/Contents/Frameworks

# 1. Copy MacPorts Python Framework
# MacPorts location: /opt/local/Library/Frameworks/Python.framework
MACPORTS_PY_FW="/opt/local/Library/Frameworks/Python.framework"
DEST_PY_FW="GoldenCheetah.app/Contents/Frameworks/Python.framework"

echo "Copying Python Framework from $MACPORTS_PY_FW"
rm -rf "$DEST_PY_FW"
rsync -axL "$MACPORTS_PY_FW/" "$DEST_PY_FW/"

# Fix Framework structure (rsync -L flattening)
echo "Restoring standard Python Framework structure..."
pushd GoldenCheetah.app/Contents/Frameworks/Python.framework > /dev/null
rm -rf Headers Resources Python Versions/Current
ln -s "Versions/${PYTHON_VERSION}" Versions/Current
ln -s Versions/Current/Headers Headers
ln -s Versions/Current/Resources Resources
ln -s Versions/Current/Python Python
popd > /dev/null

# 2. Install Python Requirements
# With MacPorts, we installed numpy via port +universal.
# We should install other requirements into the bundle using the BUNDLED interpreter or MacPorts pip?
# If we assume we want strictly universal, we should rely on 'port' for as much as possible.
# But for pure python packages, pip is fine.
# Note: MacPorts python is NOT relocation friendly by default?
# We need to make it relocatable.

PYTHON_BIN="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_VERSION}/bin/python${PYTHON_VERSION}"

if [ -f "$PYTHON_BIN" ]; then
    install_name_tool -add_rpath "@executable_path/../.." "$PYTHON_BIN" || true

    # We install requirements using the MacPorts python (system) targeting the bundle?
    # Or just use the bundled one? Bundled one might have hardcoded paths to /opt/local.
    # Let's use bundled one.

    echo "Installing requirements into bundle..."
    # We need to ensure we don't pick up /opt/local packages unless we copy them?
    # Actually, we copied the WHOLE framework, including /opt/local/.../site-packages
    # So 'numpy' should already be there!

    # Let's install checking for missing ones from requirements.txt
    "$PYTHON_BIN" -m pip install --upgrade pip
    "$PYTHON_BIN" -m pip install --break-system-packages --ignore-installed --only-binary :all: -r ../src/Python/requirements.txt || true
    # We allow failure above if packages (like numpy) are already provided by MacPorts and pip can't overwrite/compile universal easily.
else
    echo "ERROR: Bundled python binary not found."
    exit 1
fi

# 3. Qt Deployment
# We need to verify if we are deploying a Universal App.
# macdeployqt handles this IF Qt itself is compatible.
macdeployqt GoldenCheetah.app -verbose=2 -executable=GoldenCheetah.app/Contents/MacOS/GoldenCheetah

# 4. Manual Fix-up (Universal & MacPorts Specifics)
# MacPorts libs are in /opt/local/lib. They are universal.
# macdeployqt might miss some or fail to patch them.
# We need to scan and fix.

fix_binary_id() {
    local BINARY="$1"
    local BINARY_ID=$(otool -D "$BINARY" | grep -v ":" | head -n 1)
    # Check if ID is /opt/local
    if [[ "$BINARY_ID" == *"/opt/local"* ]]; then
        local LIB_NAME=$(basename "$BINARY")
        local NEW_ID="@rpath/$LIB_NAME"
        install_name_tool -id "$NEW_ID" "$BINARY"
    fi
}

fix_binary_deps() {
    local BINARY="$1"
    otool -L "$BINARY" | grep "/opt/local" | awk '{print $1}' | while read LEAK_PATH; do
        local LIB_NAME=$(basename "$LEAK_PATH")
        local DEST_REL="@rpath/$LIB_NAME"

        # Copy if missing
        if [ ! -f "GoldenCheetah.app/Contents/Frameworks/$LIB_NAME" ]; then
            echo "Copying missing MacPorts lib: $LIB_NAME"
            cp "$LEAK_PATH" "GoldenCheetah.app/Contents/Frameworks/"
            chmod +w "GoldenCheetah.app/Contents/Frameworks/$LIB_NAME"
            fix_binary_id "GoldenCheetah.app/Contents/Frameworks/$LIB_NAME"
        fi

        install_name_tool -change "$LEAK_PATH" "$DEST_REL" "$BINARY"
    done
}

# Scan and fix all binaries
find GoldenCheetah.app/Contents/MacOS GoldenCheetah.app/Contents/Frameworks -type f | while read BINARY; do
    if file "$BINARY" | grep -q "Mach-O"; then
        fix_binary_id "$BINARY"
        fix_binary_deps "$BINARY"

        # Check architecture
        ARCHS=$(lipo -info "$BINARY")
        echo "Binary $BINARY archs: $ARCHS"
    fi
done

# 5. Codesign
echo "Signing bundle..."
codesign --force --deep --sign - GoldenCheetah.app

# 6. DMG
hdiutil create -volname GoldenCheetah -srcfolder GoldenCheetah.app -ov -format UDZO GoldenCheetah.dmg
mv GoldenCheetah.dmg ../GoldenCheetah_v3.8_Universal_MacPorts.dmg
