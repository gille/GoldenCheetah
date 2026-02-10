#!/bin/bash
set -ev

: "${MACOSX_DEPLOYMENT_TARGET:=12.0}"
: "${PYTHON_VERSION:=3.11}"

export MACOSX_DEPLOYMENT_TARGET
export PATH=/opt/local/bin:/opt/local/sbin:$PATH

# Locate MacPorts Python
# MacPorts python 3.11 is at /opt/local/bin/python3.11
PYTHON_BIN="/opt/local/bin/python${PYTHON_VERSION}"

echo "Using MacPorts configuration..."
echo "MACOSX_DEPLOYMENT_TARGET: $MACOSX_DEPLOYMENT_TARGET"

# Configure gcconfig.pri
CONFIG_FILE="src/gcconfig.pri"
cp src/gcconfig.pri.in "$CONFIG_FILE"
cp qwt/qwtconfig.pri.in qwt/qwtconfig.pri

# Source common functions
source $(dirname "$0")/before_build_common.sh

# 1. Common Config (App Name, Release, Defines)
add_common_config "$CONFIG_FILE"

# Use MacPorts bison (yacc)
append_config "QMAKE_YACC = /opt/local/bin/bison"
sed -i "" "s|#QMAKE_MOVE = cp|QMAKE_MOVE = cp|" src/gcconfig.pri
append_config "LIBZ_LIBS = -lz"

# MacPorts Specific: Universal Archs
append_config "CONFIG += universal_archs"

# Force QWT to build universally by injecting arch flags directly
echo "QMAKE_APPLE_DEVICE_ARCHS = x86_64 arm64" >> qwt/qwtconfig.pri

# 2. Paths
# We use standard Qt from install-qt-action (which is universal dual-arch).
# So we do NOT force MacPorts lrelease.
# QMAKE_LRELEASE will default to $$[QT_INSTALL_BINS]/lrelease in src.pro
# add_config "QMAKE_LRELEASE = /opt/local/libexec/qt6/bin/lrelease"

# 3. Dependencies from MacPorts

# GSL
sed_i "s|#GSL_INCLUDES =.*|GSL_INCLUDES = /opt/local/include|" "$CONFIG_FILE"
sed_i "s|#GSL_LIBS =.*|GSL_LIBS = -L/opt/local/lib -lgsl -lgslcblas|" "$CONFIG_FILE"

# ICAL (Local Build)
ICAL_PATH="$(pwd)/libical-install"
if [ -d "$ICAL_PATH" ]; then
    sed_i "s|#ICAL_INSTALL =.*|ICAL_INSTALL = $ICAL_PATH|" "$CONFIG_FILE"
    sed_i "s|#ICAL_INCLUDE =.*|ICAL_INCLUDE = $ICAL_PATH/include|" "$CONFIG_FILE"
    sed_i "s|#ICAL_LIBS    =.*|ICAL_LIBS = -L$ICAL_PATH/lib -lical|" "$CONFIG_FILE"
fi

# LIBUSB
sed_i "s|#LIBUSB_INSTALL =.*|LIBUSB_INSTALL = /opt/local|" "$CONFIG_FILE"
sed_i "s|#LIBUSB_INCLUDE =.*|LIBUSB_INCLUDE = /opt/local/include/libusb-1.0|" "$CONFIG_FILE"
sed_i "s|#LIBUSB_LIBS    =.*|LIBUSB_LIBS = -L/opt/local/lib -lusb-1.0|" "$CONFIG_FILE"
# LIBUSB_USE_V_1 handled by common

# SAMPLERATE
sed_i "s|#SAMPLERATE_INSTALL =.*|SAMPLERATE_INSTALL = /opt/local|" "$CONFIG_FILE"
sed_i "s|#SAMPLERATE_INCLUDE =.*|SAMPLERATE_INCLUDE = /opt/local/include|" "$CONFIG_FILE"
# Note: SAMPLERATE_LIBS placeholder in pri.in is '#SAMPLERATE_LIBS = /usr/local/lib/libsamplerate.a' (line 236)
# It doesn't have .* at end, but better match loosely.
sed_i "s|#SAMPLERATE_LIBS =.*|SAMPLERATE_LIBS = -L/opt/local/lib -lsamplerate|" "$CONFIG_FILE"

# PYTHON
# We use MacPorts python
# Includes: /opt/local/Library/Frameworks/Python.framework/Versions/3.11/include/python3.11
# Libs: -L/opt/local/Library/Frameworks/Python.framework/Versions/3.11/lib -lpython3.11
PY_FRAMEWORK="/opt/local/Library/Frameworks/Python.framework/Versions/3.11"
# GC_WANT_PYTHON handled by common
sed_i "s|#PYTHONINCLUDES =|PYTHONINCLUDES = -I${PY_FRAMEWORK}/include/python3.11|" "$CONFIG_FILE"
sed_i "s|#PYTHONLIBS =|PYTHONLIBS = -L${PY_FRAMEWORK}/lib -lpython3.11|" "$CONFIG_FILE"

# R
# Use manual universal framework
R_FRAMEWORK="$(pwd)/R-Universal/R.framework"
if [ -d "$R_FRAMEWORK" ]; then
    echo "Using Local R Universal Framework: $R_FRAMEWORK"
    # Use Headers symlink if present, fall back to Resources/include
    if [ -d "$R_FRAMEWORK/Headers" ] || [ -L "$R_FRAMEWORK/Headers" ]; then
        R_HEADERS="$R_FRAMEWORK/Headers"
    else
        R_HEADERS="$R_FRAMEWORK/Resources/include"
    fi
    sed_i "s|#RINCLUDES =|RINCLUDES = -I${R_HEADERS}|" "$CONFIG_FILE"
    # For framework linking, we point to the parent directory
    # -F$(pwd)/R-Universal -framework R
    sed_i "s|#RLIBS =|RLIBS = -F$(dirname "$R_FRAMEWORK") -framework R|" "$CONFIG_FILE"
else
    # Fallback (shouldn't happen if install script ran)
    echo "WARNING: Local R Universal Framework not found. Falling back to port contents..."
    R_H=$(port -q contents R | grep -m1 "R.h$")
    if [ -n "$R_H" ]; then
        R_HEADERS=$(dirname "$R_H")
        R_FRAMEWORK_DIR=$(dirname "$R_HEADERS")
        R_FRAMEWORK_CONTAINER=$(dirname "$R_FRAMEWORK_DIR")
        sed_i "s|#RINCLUDES =|RINCLUDES = -I${R_HEADERS}|" "$CONFIG_FILE"
        sed_i "s|#RLIBS =|RLIBS = -F${R_FRAMEWORK_CONTAINER} -framework R|" "$CONFIG_FILE"
    fi
fi

# SRMIO (Local Build)
SRMIO_PATH="$(pwd)/srmio-install"
if [ -d "$SRMIO_PATH" ]; then
    sed_i "s|#SRMIO_INSTALL =.*|SRMIO_INSTALL = $SRMIO_PATH|" "$CONFIG_FILE"
    # DEFINES += GC_HAVE_SRMIO auto-detected by src.pro if SRMIO_INSTALL is set
fi

# D2XX (Local)
if [ -d "D2XX" ]; then
    # line 161: #D2XX_INCLUDE =
    sed_i "s|#D2XX_INCLUDE =.*|D2XX_INCLUDE = $(pwd)/D2XX|" "$CONFIG_FILE"
    # line 162: #D2XX_LIBS    =
    sed_i "s|#D2XX_LIBS    =.*|D2XX_LIBS = -L$(pwd)/D2XX -lftd2xx.1.4.24|" "$CONFIG_FILE"
    # DEFINES += GC_HAVE_D2XX auto-detected by src.pro if D2XX_INCLUDE is set
fi

# Secret patching
patch_secrets

# Version
if [[ "$GITHUB_REF_TYPE" == "tag" ]]; then
    append_config "DEFINES+=GC_VERSION=$GITHUB_REF_NAME"
fi

# Translations
lupdate src/src.pro
