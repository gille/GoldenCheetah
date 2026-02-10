#!/bin/bash
set -e

# github/macos/sign_bundle.sh
# Usage: ./sign_bundle.sh <AppBundlePath> <PythonVersion>
# Example: ./sign_bundle.sh GoldenCheetah.app 3.11

APP_BUNDLE="$1"
PYTHON_VERSION="$2"

if [ -z "$APP_BUNDLE" ] || [ -z "$PYTHON_VERSION" ]; then
    echo "Usage: $0 <AppBundlePath> <PythonVersion>"
    exit 1
fi

echo "=== Signing Refactor: Fixing and Signing Bundle '$APP_BUNDLE' for Python $PYTHON_VERSION ==="

# Helper: Fix the ID of a binary to be relative (@rpath)
fix_binary_id() {
    local BINARY="$1"
    # Ignore if not a binary
    if ! file "$BINARY" | grep -q "Mach-O"; then
        return
    fi

    local BINARY_ID=$(otool -D "$BINARY" | grep -v ":" | head -n 1)

    # Ensure writable
    chmod +w "$BINARY"

    # Check if ID is a system path (excluding /System/Library and /usr/lib which are OS libs)
    # We want to catch Homebrew, /usr/local, User paths, AND /Library/Frameworks (std python install)
    if [[ "$BINARY_ID" == *"/opt/homebrew"* ]] || [[ "$BINARY_ID" == *"/usr/local"* ]] || [[ "$BINARY_ID" == *"/Users"* ]] || [[ "$BINARY_ID" == *"/Library/Frameworks"* ]]; then
        local NEW_ID=""
        if [[ "$BINARY" == *".framework"* ]]; then
            # Extract framework relative path: .../Foo.framework/Versions/A/Foo -> Foo.framework/Versions/A/Foo
            local REL_PATH=$(echo "$BINARY" | sed -E 's/.*\/([^\/]+\.framework.*)/\1/')
            NEW_ID="@rpath/$REL_PATH"
        else
            # Flat lib: libfoo.dylib
            local LIB_NAME=$(basename "$BINARY")
            NEW_ID="@rpath/$LIB_NAME"
        fi

        echo "  Fixing ID for $BINARY"
        echo "    Old: $BINARY_ID"
        echo "    New: $NEW_ID"
        install_name_tool -id "$NEW_ID" "$BINARY"
    fi
}

# Helper: Fix dependencies of a binary
fix_binary_deps() {
    local BINARY="$1"
    # Ignore if not a binary
    if ! file "$BINARY" | grep -q "Mach-O"; then
        return
    fi
    
    # Check deps - Look for Homebrew, MacPorts (/opt/local), User paths
    otool -L "$BINARY" | grep -E "(/usr/local/|/opt/homebrew/|/opt/local/|/Users/|/Library/Frameworks/)" | grep -v "/System/" | awk '{print $1}' | while read LEAK_PATH; do
        local DEST_REL=""
        if [[ "$LEAK_PATH" == *".framework"* ]]; then
             local REL_PATH=$(echo "$LEAK_PATH" | sed -E 's/.*\/([^\/]+\.framework.*)/\1/')
             DEST_REL="@rpath/$REL_PATH"
        else
             local LIB_NAME=$(basename "$LEAK_PATH")
             # Check if we have it in Frameworks
             if [ -f "$APP_BUNDLE/Contents/Frameworks/$LIB_NAME" ]; then
                  DEST_REL="@rpath/$LIB_NAME"
             else
                  if [ -f "$LEAK_PATH" ]; then
                       echo "  Copying missing lib $LIB_NAME to bundle from $LEAK_PATH..."
                       cp "$LEAK_PATH" "$APP_BUNDLE/Contents/Frameworks/"
                       chmod +w "$APP_BUNDLE/Contents/Frameworks/$LIB_NAME"
                       # Recursively fix the new lib
                       fix_binary_id "$APP_BUNDLE/Contents/Frameworks/$LIB_NAME"
                       fix_binary_deps "$APP_BUNDLE/Contents/Frameworks/$LIB_NAME"
                       DEST_REL="@rpath/$LIB_NAME"
                  else
                       echo "  WARNING: Lib $LIB_NAME not found in bundle OR system ($LEAK_PATH)."
                  fi
             fi
        fi

        if [ -n "$DEST_REL" ]; then
             echo "  Relinking dep $LEAK_PATH -> $DEST_REL in $BINARY"
             install_name_tool -change "$LEAK_PATH" "$DEST_REL" "$BINARY"
        fi
    done
}

# 0. cleanup static archives
find "$APP_BUNDLE/Contents/Frameworks" -name "*.a" -delete

# 1. QtWebEngineProcess
QWEBVIEW_APP="$APP_BUNDLE/Contents/Frameworks/QtWebEngineCore.framework/Versions/A/Helpers/QtWebEngineProcess.app/Contents/MacOS/QtWebEngineProcess"
if [ -f "$QWEBVIEW_APP" ]; then
    echo "Patching QtWebEngineProcess..."
    if ! otool -l "$QWEBVIEW_APP" | grep -A5 LC_RPATH | grep -q "@executable_path/../../../../../../../"; then
        install_name_tool -add_rpath "@executable_path/../../../../../../../" "$QWEBVIEW_APP"
    fi
    fix_binary_deps "$QWEBVIEW_APP"
fi

# 2. Python Binaries
echo "Patching Python binaries..."
PY_BIN_DIR="$APP_BUNDLE/Contents/Frameworks/Python.framework/Versions/Current/bin"
for BIN in "python3" "python${PYTHON_VERSION}"; do
    PYTHON_BIN="$PY_BIN_DIR/$BIN"
    if [ -f "$PYTHON_BIN" ]; then
        echo "  Patching $BIN at $PYTHON_BIN"
        # We need RPATH to point to Contents/Frameworks so @rpath/Python.framework resolves correctly.
        # From bin/python3.11:
        # .. -> Versions/3.11
        # ../.. -> Versions
         # ../../.. -> Python.framework
        # ../../../.. -> Frameworks
        # ../../.. -> Python.framework
        # ../../../.. -> Frameworks
        if otool -l "$PYTHON_BIN" | grep -A5 LC_RPATH | grep -E -q "@executable_path/\.\./\.\.( |$)"; then
            install_name_tool -delete_rpath "@executable_path/../.." "$PYTHON_BIN"
        fi
        if ! otool -l "$PYTHON_BIN" | grep -A5 LC_RPATH | grep -E -q "@executable_path/\.\./\.\./\.\./\.\.( |$)"; then
            install_name_tool -add_rpath "@executable_path/../../../.." "$PYTHON_BIN"
        fi
        fix_binary_deps "$PYTHON_BIN"
    fi
done

PYTHON_APP_BIN="$APP_BUNDLE/Contents/Frameworks/Python.framework/Versions/Current/Resources/Python.app/Contents/MacOS/Python"
if [ -f "$PYTHON_APP_BIN" ]; then
     # Use generous RPATH
     if ! otool -l "$PYTHON_APP_BIN" | grep -A5 LC_RPATH | grep -q "@executable_path/../../../../../../.."; then
         install_name_tool -add_rpath "@executable_path/../../../../../../.." "$PYTHON_APP_BIN"
     fi
     fix_binary_deps "$PYTHON_APP_BIN"
fi

# 3. Bundling OpenSSL (Brew or MacPorts?)
# We assume if the environment has openssl installed (e.g. via brew in after_build.sh), we might want to bundle it.
# However, this script is generic. Let's inspect if Python links to system OpenSSL.
# We will use the generic fix_binary_deps logic to pull in OpenSSL if needed!
# BUT OpenSSL often needs manual ID fixing because they have version numbers.
# Let's rely on fix_binary_deps/fix_binary_id to handle it generically.

# 4. Mass Scan & Fix
echo "Scanning entire bundle for leaks..."
set +v
# Find all binaries
# Find all binaries
find "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Frameworks" "$APP_BUNDLE/Contents/PlugIns" "$APP_BUNDLE/Contents/Resources" \( -name "GoldenCheetah" -o -name "*.dylib" -o -name "*.so" -o -perm +111 \) -type f | sort -u | while read BINARY; do
    if file "$BINARY" | grep -q "Mach-O"; then
        fix_binary_id "$BINARY"
        fix_binary_deps "$BINARY"
    fi
done
set -v

# 5. Fix Python Framework Bundle Structure (Critical for codesign)
echo "Verifying Python Framework Structure for Codesign..."
PY_FW_ROOT="$APP_BUNDLE/Contents/Frameworks/Python.framework"
PY_VER_DIR="$PY_FW_ROOT/Versions/$PYTHON_VERSION"

# Ensure Versions/Current points to Versions/X.Y
if [ -L "$PY_FW_ROOT/Versions/Current" ]; then
    rm "$PY_FW_ROOT/Versions/Current"
fi
ln -s "$PYTHON_VERSION" "$PY_FW_ROOT/Versions/Current"

# Ensure root symlinks
rm -rf "$PY_FW_ROOT/"{Headers,Resources,Python}
ln -s "Versions/Current/Headers" "$PY_FW_ROOT/Headers"
ln -s "Versions/Current/Resources" "$PY_FW_ROOT/Resources"
ln -s "Versions/Current/Python" "$PY_FW_ROOT/Python"

# Ensure Info.plist exists in Resources
if [ ! -f "$PY_VER_DIR/Resources/Info.plist" ]; then
    echo "WARNING: Info.plist missing in Python Framework Resources!"
    echo "Attempting to create minimal Info.plist..."
    mkdir -p "$PY_VER_DIR/Resources"
    cat > "$PY_VER_DIR/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>
    <key>CFBundleExecutable</key>
    <string>Python</string>
    <key>CFBundleIdentifier</key>
    <string>org.python.python</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Python</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$PYTHON_VERSION</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>$PYTHON_VERSION</string>
</dict>
</plist>
EOF
fi

# 6. Signing
echo "Signing..."
# Force resign python binary components first
codesign --force --sign - --preserve-metadata=identifier,entitlements "$PY_VER_DIR/Python"
codesign --force --sign - --preserve-metadata=identifier,entitlements "$PY_VER_DIR/bin/python$PYTHON_VERSION"

# Resign all dylibs/so
echo "Resigning libraries..."
find "$APP_BUNDLE/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) -exec codesign --force --sign - {} \;

# Sign Python.app if present
PYTHON_APP="$PY_VER_DIR/Resources/Python.app"
if [ -d "$PYTHON_APP" ]; then
    echo "Signing nested Python.app..."
    codesign --force --deep --sign - --preserve-metadata=identifier,entitlements "$PYTHON_APP"
fi

echo "Signing Python.framework..."
codesign --force --sign - "$PY_FW_ROOT"

echo "Signing App Bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Verification..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" || echo "WARNING: Signature verification failed (expected for ad-hoc?)"

echo "Done."
