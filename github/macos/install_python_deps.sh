#!/bin/bash
set -e

# github/macos/install_python_deps.sh
# Usage: ./install_python_deps.sh <AppBundlePath> <PythonVersion> <RequirementsFile>
# Example: ./install_python_deps.sh GoldenCheetah.app 3.11 ../src/Python/requirements.txt

APP_BUNDLE="$1"
PYTHON_VERSION="$2"
REQ_FILE="$3"

if [ -z "$APP_BUNDLE" ] || [ -z "$PYTHON_VERSION" ] || [ -z "$REQ_FILE" ]; then
    echo "Usage: $0 <AppBundlePath> <PythonVersion> <RequirementsFile>"
    exit 1
fi

echo "=== Shared Python Install: Setup & Requirements ==="
echo "Bundle: $APP_BUNDLE"
echo "Python: $PYTHON_VERSION"
echo "Reqs:   $REQ_FILE"

# 1. Fix Framework Structure (Critical for codesign & finding paths)
# rsync -L often breaks this, turning symlinks into directories.
echo "Restoring standard Python Framework structure..."
FRAMEWORK_DIR="$APP_BUNDLE/Contents/Frameworks/Python.framework"
pushd "$FRAMEWORK_DIR" > /dev/null
rm -rf Headers Resources Python Versions/Current
ln -s "${PYTHON_VERSION}" Versions/Current
ln -s Versions/Current/Headers Headers
ln -s Versions/Current/Resources Resources
ln -s Versions/Current/Python Python
popd > /dev/null

# 2. Locate Binary
PYTHON_BIN="$FRAMEWORK_DIR/Versions/Current/bin/python${PYTHON_VERSION}"
if [ ! -f "$PYTHON_BIN" ]; then
    # Fallback to python3 if specific version binary is missing (sometimes it's just python3)
    PYTHON_BIN="$FRAMEWORK_DIR/Versions/Current/bin/python3"
fi

if [ ! -f "$PYTHON_BIN" ]; then
    echo "ERROR: Bundled python binary not found at $PYTHON_BIN"
    exit 1
fi

# 3. Patch RPATH so binary can run from within the bundle
# (Needed for pip install to work)
echo "Patching Python RPATH for execution..."
# Delete RPATH if it exists (Strict Check)
if otool -l "$PYTHON_BIN" | grep -A5 LC_RPATH | grep -E -q "@executable_path/\.\./\.\.( |$)"; then
    install_name_tool -delete_rpath "@executable_path/../.." "$PYTHON_BIN"
fi
# Add correct RPATH if missing
if ! otool -l "$PYTHON_BIN" | grep -A5 LC_RPATH | grep -E -q "@executable_path/\.\./\.\./\.\./\.\.( |$)"; then
    install_name_tool -add_rpath "@executable_path/../../../.." "$PYTHON_BIN"
fi
# Ad-hoc sign so it runs locally
codesign --force --sign - "$PYTHON_BIN"

# 4. Install Requirements
echo "Installing requirements..."
"$PYTHON_BIN" -m pip install --break-system-packages --upgrade pip setuptools wheel

# Calculate site-packages path
# We resolve the symlink 'Current' to ensure we point to the real directory
# 'GoldenCheetah.app' depends on CWD, assuming script run from build root? 
# Better to use absolute path for find if we can, or relative to CWD.
# We will use the path relative to where this script is called (usually src or parent)
# But let's trust $APP_BUNDLE is correct relative path.

PWD_CTX=$(pwd)
SITE_PACKAGES="$PWD_CTX/$FRAMEWORK_DIR/Versions/Current/lib/python${PYTHON_VERSION}/site-packages"

if [ ! -d "$SITE_PACKAGES" ]; then
    # Fallback search
    SITE_PACKAGES=$(find "$PWD_CTX/$FRAMEWORK_DIR/Versions/Current/lib" -name "python3.*" -type d | head -n 1)/site-packages
fi

echo "Target Site-Packages: $SITE_PACKAGES"
"$PYTHON_BIN" -m pip install --target "$SITE_PACKAGES" --break-system-packages --ignore-installed --no-cache-dir --prefer-binary -r "$REQ_FILE"

# 5. Cleanup (Reduce Bundle Size)
echo "Cleaning up Python Framework..."
VER_DIR="$FRAMEWORK_DIR/Versions/${PYTHON_VERSION}"
rm -rf "$VER_DIR/include"
rm -rf "$VER_DIR/share"
rm -rf "$VER_DIR/lib/python${PYTHON_VERSION}/test"
rm -rf "$VER_DIR/lib/python${PYTHON_VERSION}/idlelib"
rm -rf "$VER_DIR/lib/python${PYTHON_VERSION}/ensurepip"
# PyCache
find "$FRAMEWORK_DIR" -name "__pycache__" -type d -exec rm -rf {} +

echo "Python Installation Complete."
