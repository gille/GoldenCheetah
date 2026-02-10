#!/bin/bash
set -ev

# Helper function to find brew prefix
BREW_PREFIX=$(brew --prefix)

# Get config
cp qwt/qwtconfig.pri.in qwt/qwtconfig.pri
cp src/gcconfig.pri.in src/gcconfig.pri

# Common Config (Source early to get helpers)
source $(dirname "$0")/before_build_common.sh
CONFIG_FILE="src/gcconfig.pri"

# 1. Common Config Application
add_common_config "$CONFIG_FILE"

# Bison - find the keg-only bison
BISON_PATH="$BREW_PREFIX/opt/bison/bin/bison"
append_config "QMAKE_YACC=$BISON_PATH"

# Enable compress library
append_config "LIBZ_LIBS = -lz"

# GSL
GSL_PATH="$BREW_PREFIX/opt/gsl"
sed_i "s|#GSL_INCLUDES =.*|GSL_INCLUDES = ${GSL_PATH}/include|" "$CONFIG_FILE"
sed_i "s|#GSL_LIBS =.*|GSL_LIBS = -L${GSL_PATH}/lib -lgsl -lgslcblas -lm|" "$CONFIG_FILE"

# Define GC version string for tagged builds
if [ -n "$GITHUB_REF_NAME" ] && [[ "$GITHUB_REF_TYPE" == "tag" ]]; then
    append_config "DEFINES += \"GC_VERSION=$GITHUB_REF_NAME\""
fi

sed_i "s|#QMAKE_MOVE = cp|QMAKE_MOVE = cp|" "$CONFIG_FILE"
# Ensure we build static (Intel specific preference?)
sed_i "s|#\(CONFIG += release.*\)|\1 static |" "$CONFIG_FILE"
append_config "CONFIG += static"

sed_i "s|^#LIBZ|LIBZ|" "$CONFIG_FILE"

# SRMIO
sed_i "s|#\(SRMIO_INSTALL =.*\)|\1 /usr/local|" "$CONFIG_FILE"

# D2XX
# Update D2XX.cpp to look for dylib in Frameworks (relative to executable)
sed_i "s|libftd2xx.dylib|@executable_path/../Frameworks/libftd2xx.1.4.24.dylib|" src/FileIO/D2XX.cpp
sed_i "s|#\(D2XX_INCLUDE =.*\)|\1 ../D2XX|" "$CONFIG_FILE"
sed_i "s|#\(D2XX_LIBS    =.*\)|\1 -L../D2XX -lftd2xx|" "$CONFIG_FILE"

# ICAL
ICAL_PATH="$BREW_PREFIX/opt/libical"
sed_i "s|#\(ICAL_INSTALL =.*\)|\1 ${ICAL_PATH}|" "$CONFIG_FILE"
sed_i "s|#\(ICAL_LIBS    =.*\)|\1 -L${ICAL_PATH}/lib -lical|" "$CONFIG_FILE"

# LIBUSB
LIBUSB_PATH="$BREW_PREFIX/opt/libusb"
sed_i "s|#\(LIBUSB_INSTALL =\).*|\1 ${LIBUSB_PATH}|" "$CONFIG_FILE"
sed_i "s|#\(LIBUSB_LIBS    =.*\)|\1 -L${LIBUSB_PATH}/lib -lusb-1.0|" "$CONFIG_FILE"
# LIBUSB_USE_V_1 handled by common

# SAMPLERATE
SAMPLERATE_PATH="$BREW_PREFIX/opt/libsamplerate"
sed_i "s|#\(SAMPLERATE_INSTALL =\).*|\1 ${SAMPLERATE_PATH}|" "$CONFIG_FILE"
sed_i "s|#\(SAMPLERATE_LIBS =\).*|\1 -L${SAMPLERATE_PATH}/lib -lsamplerate|" "$CONFIG_FILE"

# LMFIT
sed_i "s|#\(LMFIT_INSTALL =\).*|\1 /usr/local|" "$CONFIG_FILE"

sed_i "s|#\(DEFINES += GC_HAVE_LION*\)|\1|" "$CONFIG_FILE"

# Python (common handles it, but verify/ensure)
# sed_i "s|#\(DEFINES += GC_WANT_PYTHON\)\.*|\1 |" "$CONFIG_FILE"

# TrainerDay Query API already added by common config

# macOS version config
append_config "QMAKE_MACOSX_DEPLOYMENT_TARGET = 11.0"

# Secret patching
patch_secrets

# Update translations
lupdate src/src.pro
