#!/bin/bash
set -ev

: "${GC_VERSION:=3.8}"
: "${MACOSX_DEPLOYMENT_TARGET:=12.0}"
: "${PYTHON_VERSION:=3.11}"

export MACOSX_DEPLOYMENT_TARGET
export PATH=/opt/local/bin:/opt/local/sbin:$PATH

echo "Packaging MacPorts Universal Build..."

# 0. Clean & Prepare
cd src
export PIP_BREAK_SYSTEM_PACKAGES=1
mkdir -p GoldenCheetah.app/Contents/Frameworks

# 1. Copy MacPorts Python Framework
# MacPorts location: /opt/local/Library/Frameworks/Python.framework
MACPORTS_PY_FW="/opt/local/Library/Frameworks/Python.framework"
DEST_PY_FW="GoldenCheetah.app/Contents/Frameworks/Python.framework"

echo "Copying Python Framework from $MACPORTS_PY_FW"
rm -rf "$DEST_PY_FW"
rsync -axL "$MACPORTS_PY_FW/" "$DEST_PY_FW/"

# 1.5 Copy R Framework (Universal)
R_FW_SRC="../R-Universal/R.framework"
if [ -d "$R_FW_SRC" ]; then
    echo "Copying R Framework from $R_FW_SRC"
    DEST_R_FW="GoldenCheetah.app/Contents/Frameworks/R.framework"
    rm -rf "$DEST_R_FW"
    # Use -a to preserve symlinks (Versions/Current -> 4.x)
    rsync -a "$R_FW_SRC/" "$DEST_R_FW/"
    
    # Clean up Headers to save space
    rm -rf "$DEST_R_FW/Headers" "$DEST_R_FW/Versions/*/Headers" "$DEST_R_FW/Versions/*/Resources/doc"

    # Optimization: Remove Tests and Help 
    # (Help is large, but might be needed? We'll remove tests for sure)
    rm -rf "$DEST_R_FW/Versions/*/Resources/tests"
    rm -rf "$DEST_R_FW/Versions/*/Resources/library/*/tests"
    # Optional: Remove help if size is critical (commented out for now until confirmed sage)
    # rm -rf "$DEST_R_FW/Versions/*/Resources/library/*/help"

    # Fix Broken Symlinks (fontconfig often has symlinks to /opt/X11/...)
    # This causes cp errors when moving the bundle.
    find "$DEST_R_FW" -name "conf.d" -type d | while read CONFD; do
        find "$CONFD" -type l ! -exec test -e {} \; -delete
    done

    # Fix Structure for Codesign
    # Codesign requires frameworks to NOT have unsealed content in the root (only Versions + symlinks).
    
    # 1. Move Licenses to App Resources (Preserve Legal)
    mkdir -p "GoldenCheetah.app/Contents/Resources/Licenses"
    if [ -f "$DEST_R_FW/COPYING" ]; then
        mv "$DEST_R_FW/COPYING" "GoldenCheetah.app/Contents/Resources/Licenses/R-COPYING"
    fi
    if [ -f "$DEST_R_FW/SVN-REVISION" ]; then
        mv "$DEST_R_FW/SVN-REVISION" "GoldenCheetah.app/Contents/Resources/Licenses/R-SVN-REVISION"
    fi

    # 2. Remove loose files in root (COPYING, SVN-REVISION, etc.)
    echo "Cleaning R.framework root structure..."
    find "$DEST_R_FW" -maxdepth 1 -type f -delete

    # Ensure Symlinks are correct
    # Some R installs put PrivateHeaders in root?
    rm -rf "$DEST_R_FW/PrivateHeaders" "$DEST_R_FW/Libraries"
    
    # Re-create root symlinks if missing/broken
    # (Checking if Versions/Current exists first)
    if [ -d "$DEST_R_FW/Versions/Current" ]; then
        rm -f "$DEST_R_FW/Resources" "$DEST_R_FW/Headers" "$DEST_R_FW/R"
        ln -sf Versions/Current/Resources "$DEST_R_FW/Resources"
        ln -sf Versions/Current/Headers "$DEST_R_FW/Headers"
        ln -sf Versions/Current/R "$DEST_R_FW/R" # Binary link if exists? R framework binary usually named R
        # Wait, R framework binary is usually "R" inside Versions/Current/R ? No, it's Versions/Current/R (binary) or Versions/Current/Resources/lib/libR.dylib?
        # Standard Mac Framework: Binary "R" at top level of Version.
        # Let's check if Versions/Current/R exists.
    fi
else
    echo "WARNING: R Framework not found at $R_FW_SRC. R integration may fail."
fi

# Fix Framework structure (rsync -L flattening)
# 2. Install Python Requirements & Fix Framework
# Consolidated into shared script
echo "Calling shared Python install script..."
bash ../github/macos/install_python_deps.sh "GoldenCheetah.app" "${PYTHON_VERSION}" "../src/Python/requirements.txt"

# 3. Qt Deployment
# Consolidated into shared script
echo "Calling shared Qt packaging script..."
bash ../github/macos/package_qt.sh "GoldenCheetah.app"

# 4.5 Copy D2XX (libftd2xx)
# It is built/downloaded locally in ../D2XX
D2XX_SRC="../D2XX/libftd2xx.1.4.24.dylib"
if [ -f "$D2XX_SRC" ]; then
    echo "Copying D2XX from $D2XX_SRC"
    cp "$D2XX_SRC" "GoldenCheetah.app/Contents/Frameworks/libftd2xx.dylib"
    chmod +w "GoldenCheetah.app/Contents/Frameworks/libftd2xx.dylib"
    
    # Fix ID
    install_name_tool -id "@rpath/libftd2xx.dylib" "GoldenCheetah.app/Contents/Frameworks/libftd2xx.dylib"
    
    # Fix main binary linking
    # The binary might link to "libftd2xx.dylib" (no path) or the full path depending on build
    # We force it to @rpath
    echo "Linking GoldenCheetah to @rpath/libftd2xx.dylib..."
    if otool -L "GoldenCheetah.app/Contents/MacOS/GoldenCheetah" | grep -q "libftd2xx.dylib"; then
        install_name_tool -change "libftd2xx.dylib" "@rpath/libftd2xx.dylib" "GoldenCheetah.app/Contents/MacOS/GoldenCheetah"
    fi
    if otool -L "GoldenCheetah.app/Contents/MacOS/GoldenCheetah" | grep -q "/usr/local/lib/libftd2xx.dylib"; then
        install_name_tool -change "/usr/local/lib/libftd2xx.dylib" "@rpath/libftd2xx.dylib" "GoldenCheetah.app/Contents/MacOS/GoldenCheetah"
    fi
else
    echo "WARNING: D2XX lib not found at $D2XX_SRC"
fi

# 4.6 Copy Libical (Manual Universal Build)
ICAL_LIB_DIR="../libical-install/lib"
if [ -d "$ICAL_LIB_DIR" ]; then
    echo "Copying Libical dylibs from $ICAL_LIB_DIR"
    # Copy all dylibs (libical, libicalss, libicalvcal) to cover dependencies
    cp "$ICAL_LIB_DIR"/*.dylib "GoldenCheetah.app/Contents/Frameworks/"
    chmod +w "GoldenCheetah.app/Contents/Frameworks/"*.dylib
else
    echo "ERROR: Libical install dir not found at $ICAL_LIB_DIR"
fi

# Using shared signing script
echo "Calling shared signing script..."
bash ../github/macos/sign_bundle.sh "GoldenCheetah.app" "${PYTHON_VERSION}"

# 6. DMG
hdiutil create -volname GoldenCheetah -srcfolder GoldenCheetah.app -ov -format UDZO GoldenCheetah.dmg
mv GoldenCheetah.dmg "../GoldenCheetah_v${GC_VERSION}_Universal.dmg"
