#!/bin/bash
set -ev
cd src

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

# Fix the Python Framework structure broken by rsync -L
# rsync -L turns symlinks into directories, confusing codesign. We restore the standard structure.
echo "Restoring standard Python Framework structure..."
pushd GoldenCheetah.app/Contents/Frameworks/Python.framework > /dev/null
rm -rf Headers Resources Python Versions/Current
ln -s "$PYTHON_FULL_VER" Versions/Current
ln -s Versions/Current/Headers Headers
ln -s Versions/Current/Resources Resources
ln -s Versions/Current/Python Python
popd > /dev/null

# Locate actual site-packages -- NO LONGER NEEDED (we install fresh)
# But we need verify pip is present
PYTHON_BIN="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3"

echo "Installing requirements into bundle..."
if [ -f "$PYTHON_BIN" ]; then
    install_name_tool -add_rpath "@executable_path/../.." "$PYTHON_BIN" || true

    echo "Running pip install using bundled python: $PYTHON_BIN"
    #"$PYTHON_BIN" -m pip install --upgrade pip
    "$PYTHON_BIN" -m pip install --break-system-packages --only-binary :all: -r ../src/Python/requirements.txt
else
    echo "ERROR: Bundled python binary not found at $PYTHON_BIN"
    exit 1
fi

SITE_PACKAGES_SRC=$( "$PYTHON_BIN" -c "import numpy; import os; print(os.path.dirname(os.path.dirname(numpy.__file__)))" )
echo "Verified Site Packages at: $SITE_PACKAGES_SRC"

# Remove direct_url.json metadata which may contain absolute paths to the build machine
# This prevents pip inspect from reporting build paths
find "$SITE_PACKAGES_SRC" -name "direct_url.json" -delete

# Fix pip binaries
echo "Fixing pip binaries to be relocatable..."
PYTHON_BIN_DIR="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/bin"
if [ -d "$PYTHON_BIN_DIR" ]; then
    for PIP_BIN in pip pip3 pip${PYTHON_FULL_VER}; do
        if [ -f "$PYTHON_BIN_DIR/$PIP_BIN" ]; then
            rm "$PYTHON_BIN_DIR/$PIP_BIN"
            cat > "$PYTHON_BIN_DIR/$PIP_BIN" <<EOF
#!/bin/sh
exec "\$(dirname "\$0")/python${PYTHON_FULL_VER}" -m pip "\$@"
EOF
            chmod +x "$PYTHON_BIN_DIR/$PIP_BIN"
        fi
    done
fi

# Patch _sysconfigdata
echo "Patching _sysconfigdata..."
SYSCONFIG_FILE=$(find "GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/lib/python${PYTHON_FULL_VER}" -name "_sysconfigdata_*.py" | head -n 1)
if [ -f "$SYSCONFIG_FILE" ]; then
    echo "Patching $SYSCONFIG_FILE to be relocatable..."
    # Use python to safely replace the string literal, avoiding sed quoting issues
    # PYTHON_PREFIX is set at top of script (equivalent to BREW_PYTHON_ROOT)
    python3 <<EOF
import sys
import os

filepath = "$SYSCONFIG_FILE"
prefix = "$PYTHON_PREFIX"

if os.path.exists(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Ensure sys is imported
    if "import sys" not in content:
        content = "import sys\n" + content

    # Replace absolute prefix with f-string using sys.prefix
    # This preserves implicit string concatenation (e.g. f'...' '...')
    content = content.replace("'" + prefix, "f'{sys.prefix}")
    content = content.replace('"' + prefix, 'f"{sys.prefix}')

    with open(filepath, 'w') as f:
        f.write(content)
EOF
fi

# Update ID of the python library
echo "Updating Python library ID..."
install_name_tool -id @executable_path/../Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/Python ./GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/Python

# Update GoldenCheetah binary
echo "Updating GoldenCheetah binary dependency..."
GC_BIN="./GoldenCheetah.app/Contents/MacOS/GoldenCheetah"
# Find the absolute path it currently links to
OLD_GC_PATH=$(otool -L "$GC_BIN" | grep "Python.framework" | grep -v executable_path | awk '{print $1}' | head -n 1)
if [ -n "$OLD_GC_PATH" ]; then
    install_name_tool -change "$OLD_GC_PATH" "@executable_path/../Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/Python" "$GC_BIN"
fi

# Update Python binary dependencies
PYTHON_BIN="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/bin/python${PYTHON_FULL_VER}"
if [ -f "$PYTHON_BIN" ]; then
    # Fix references to the old framework path
    otool -L "$PYTHON_BIN" | grep "Python" | grep "/" | grep -v "@executable_path" | awk '{print $1}' | while read OLD_PATH; do
        install_name_tool -change "$OLD_PATH" "@executable_path/../Python" "$PYTHON_BIN"
    done
fi

# Update all dylibs inside the framework
echo "Fixing dylibs inside framework..."
find GoldenCheetah.app/Contents/Frameworks/Python.framework -name "libpython*.dylib" -type f | while read LIB; do
    OLD_LIB_PATH=$(otool -L "$LIB" | grep "Python.framework" | grep -v executable_path | awk '{print $1}' | head -n 1)
    if [ -n "$OLD_LIB_PATH" ]; then
        install_name_tool -change "$OLD_LIB_PATH" "@executable_path/../Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/Python" "$LIB"
    fi
    install_name_tool -id "@executable_path/../Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/lib/$(basename $LIB)" "$LIB"
done

# Copied from AppVeyor: Bundling OpenSSL
echo "Bundling OpenSSL libraries..."
OPENSSL_PREFIX=$(brew --prefix openssl@3)
if [ -d "$OPENSSL_PREFIX" ]; then
    echo "Found OpenSSL at $OPENSSL_PREFIX"
    DEST_FRAMEWORKS="GoldenCheetah.app/Contents/Frameworks"

    # Copy libs
    cp "$OPENSSL_PREFIX/lib/libssl.3.dylib" "$DEST_FRAMEWORKS/"
    cp "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "$DEST_FRAMEWORKS/"
    chmod +w "$DEST_FRAMEWORKS/libssl.3.dylib" "$DEST_FRAMEWORKS/libcrypto.3.dylib"

    # Fix IDs
    install_name_tool -id "@loader_path/libssl.3.dylib" "$DEST_FRAMEWORKS/libssl.3.dylib"
    install_name_tool -id "@loader_path/libcrypto.3.dylib" "$DEST_FRAMEWORKS/libcrypto.3.dylib"
    install_name_tool -change "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" "$DEST_FRAMEWORKS/libssl.3.dylib"

    # Fix Python extensions (_ssl, _hashlib)
    DYNLOAD_DIR="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/lib/python${PYTHON_FULL_VER}/lib-dynload"
    if [ -d "$DYNLOAD_DIR" ]; then
        for EXT in _ssl _hashlib; do
            EXT_FILE=$(find "$DYNLOAD_DIR" -name "${EXT}.*.so" | head -n 1)
            if [ -n "$EXT_FILE" ]; then
                echo "Patching $EXT_FILE"
                # Update linkage to find libssl/libcrypto relative to _ssl.so
                # Path is @loader_path/../../../../../../libssl.3.dylib
                install_name_tool -change "$OPENSSL_PREFIX/lib/libssl.3.dylib" "@loader_path/../../../../../../libssl.3.dylib" "$EXT_FILE"
                install_name_tool -change "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "@loader_path/../../../../../../libcrypto.3.dylib" "$EXT_FILE"
            fi
        done
    fi
else
    echo "WARNING: OpenSSL prefix not found!"
fi

# Copied from AppVeyor: Bundling OpenSSL
echo "Bundling OpenSSL libraries..."
OPENSSL_PREFIX=$(brew --prefix openssl@3)
if [ -d "$OPENSSL_PREFIX" ]; then
    DEST_FRAMEWORKS="GoldenCheetah.app/Contents/Frameworks"
    cp "$OPENSSL_PREFIX/lib/libssl.3.dylib" "$DEST_FRAMEWORKS/"
    cp "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "$DEST_FRAMEWORKS/"
    chmod +w "$DEST_FRAMEWORKS/libssl.3.dylib" "$DEST_FRAMEWORKS/libcrypto.3.dylib"

    install_name_tool -id "@loader_path/libssl.3.dylib" "$DEST_FRAMEWORKS/libssl.3.dylib"
    install_name_tool -id "@loader_path/libcrypto.3.dylib" "$DEST_FRAMEWORKS/libcrypto.3.dylib"
    install_name_tool -change "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" "$DEST_FRAMEWORKS/libssl.3.dylib"

    # Fix Python extensions (_ssl, _hashlib)
    DYNLOAD_DIR="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/lib/python${PYTHON_FULL_VER}/lib-dynload"
    if [ -d "$DYNLOAD_DIR" ]; then
        for EXT in _ssl _hashlib; do
            EXT_FILE=$(find "$DYNLOAD_DIR" -name "${EXT}.*.so" | head -n 1)
            if [ -n "$EXT_FILE" ]; then
                # Update linkage to find libssl/libcrypto relative to _ssl.so
                # Path is @loader_path/../../../../../../libssl.3.dylib
                install_name_tool -change "$OPENSSL_PREFIX/lib/libssl.3.dylib" "@loader_path/../../../../../../libssl.3.dylib" "$EXT_FILE"
                install_name_tool -change "$OPENSSL_PREFIX/lib/libcrypto.3.dylib" "@loader_path/../../../../../../libcrypto.3.dylib" "$EXT_FILE"
            fi
        done
    fi
else
    echo "WARNING: OpenSSL prefix not found!"
fi

# QtDBus
echo "Copying QtDBus..."
# We need to find where Qt is.
# In GHA, we don't strictly know QTDIR unless we ask qmake.
QT_LIB_DIR=$(qmake -query QT_INSTALL_LIBS)
if [ -d "$QT_LIB_DIR/QtDBus.framework" ]; then
    cp -R "$QT_LIB_DIR/QtDBus.framework" GoldenCheetah.app/Contents/Frameworks/
fi

# D2XX linkage fix
if [ -f "../D2XX/libftd2xx.1.4.24.dylib" ]; then
    cp ../D2XX/libftd2xx.1.4.24.dylib GoldenCheetah.app/Contents/Frameworks/
    install_name_tool -id @executable_path/../Frameworks/libftd2xx.1.4.24.dylib GoldenCheetah.app/Contents/Frameworks/libftd2xx.1.4.24.dylib
fi

# Run macdeployqt (prepare bundle only, no dmg)
echo "Running macdeployqt..."
macdeployqt GoldenCheetah.app -verbose=2 -executable=GoldenCheetah.app/Contents/MacOS/GoldenCheetah

### MANUAL LEAK PATCHING ###
echo "Starting manual leak patching..."

# Helper: Fix the ID of a binary to be relative (@rpath)
fix_binary_id() {
    local BINARY="$1"
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

    # Check deps
    otool -L "$BINARY" | grep -E "(/usr/local/|/opt/homebrew/|/Users/|/Library/Frameworks/)" | grep -v "/System/" | awk '{print $1}' | while read LEAK_PATH; do
        local DEST_REL=""
        if [[ "$LEAK_PATH" == *".framework"* ]]; then
             local REL_PATH=$(echo "$LEAK_PATH" | sed -E 's/.*\/([^\/]+\.framework.*)/\1/')
             DEST_REL="@rpath/$REL_PATH"
        else
             local LIB_NAME=$(basename "$LEAK_PATH")
             if [ -f "GoldenCheetah.app/Contents/Frameworks/$LIB_NAME" ]; then
                  DEST_REL="@rpath/$LIB_NAME"
             else
                  if [ -f "$LEAK_PATH" ]; then
                       echo "  Copying missing lib $LIB_NAME to bundle from $LEAK_PATH..."
                       cp "$LEAK_PATH" "GoldenCheetah.app/Contents/Frameworks/"
                       chmod +w "GoldenCheetah.app/Contents/Frameworks/$LIB_NAME"
                       # Recursively fix the new lib
                       fix_binary_id "GoldenCheetah.app/Contents/Frameworks/$LIB_NAME"
                       fix_binary_deps "GoldenCheetah.app/Contents/Frameworks/$LIB_NAME"
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
find GoldenCheetah.app/Contents/Frameworks -name "*.a" -delete

# 1. QtWebEngineProcess
QWEBVIEW_APP="GoldenCheetah.app/Contents/Frameworks/QtWebEngineCore.framework/Versions/A/Helpers/QtWebEngineProcess.app/Contents/MacOS/QtWebEngineProcess"
if [ -f "$QWEBVIEW_APP" ]; then
    echo "Patching QtWebEngineProcess..."
    install_name_tool -add_rpath "@executable_path/../../../../../../../" "$QWEBVIEW_APP" || true
    fix_binary_deps "$QWEBVIEW_APP"
fi

# 2. Python Binaries
echo "Patching Python binaries..."
# Manual RPATH fix for python binaries so they can find @rpath/Python.framework...
PYTHON_BIN="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3"
if [ -f "$PYTHON_BIN" ]; then
    install_name_tool -add_rpath "@executable_path/../.." "$PYTHON_BIN" || true
    fix_binary_deps "$PYTHON_BIN"
fi

PYTHON_APP_BIN="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/Current/Resources/Python.app/Contents/MacOS/Python"
if [ -f "$PYTHON_APP_BIN" ]; then
     # This one is usually @executable_path/../../../../.. away from Frameworks root?
     # It's deep inside Resoures.
     # Let's give it a generous RPATH to Frameworks root.
     install_name_tool -add_rpath "@executable_path/../../../../../../.." "$PYTHON_APP_BIN" || true
     fix_binary_deps "$PYTHON_APP_BIN"
fi

# 3. Mass Scan
echo "Scanning entire bundle for other leaks..."
set +v
# Use user's improved find command
find GoldenCheetah.app/Contents/MacOS GoldenCheetah.app/Contents/Frameworks \( -name "GoldenCheetah" -o -name "*.dylib" -o -name "*.so" -o -perm +111 \) -type f | sort -u | while read BINARY; do
    if file "$BINARY" | grep -q "Mach-O"; then
        fix_binary_id "$BINARY"
        fix_binary_deps "$BINARY"
    fi
done
set -v

echo "Resigning..."
codesign --force --sign - "GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/Python"
codesign --force --sign - "GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/bin/python${PYTHON_FULL_VER}"

# Explicitly resign all .so and .dylib files in the framework (e.g. in lib-dynload)
# codesign --deep on the app bundle often skips these or fails to resign them properly
echo "Resigning all dynamic libraries in Python framework AND Contents/Frameworks..."
find "GoldenCheetah.app/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) -exec codesign --force --sign - {} \;

# Sign the nested Python.app if it exists (Inside-Out signing)
PYTHON_APP="GoldenCheetah.app/Contents/Frameworks/Python.framework/Versions/${PYTHON_FULL_VER}/Resources/Python.app"
if [ -d "$PYTHON_APP" ]; then
    echo "Signing nested Python.app..."
    codesign --force --preserve-metadata=identifier,entitlements --sign - "$PYTHON_APP"
fi

echo "Signing Python.framework..."
codesign --force --sign - "GoldenCheetah.app/Contents/Frameworks/Python.framework"

codesign --force --deep --sign - GoldenCheetah.app

echo "Creating DMG..."
hdiutil create -volname GoldenCheetah -srcfolder GoldenCheetah.app -ov -format UDZO GoldenCheetah.dmg
mv GoldenCheetah.dmg ../GoldenCheetah_v3.8_x64.dmg
