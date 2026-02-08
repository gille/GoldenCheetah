#!/bin/bash
set -ev

# Helper function to find brew prefix
BREW_PREFIX=$(brew --prefix)

# Get config
cp qwt/qwtconfig.pri.in qwt/qwtconfig.pri
cp src/gcconfig.pri.in src/gcconfig.pri

# Bison - find the keg-only bison
BISON_PATH="$BREW_PREFIX/opt/bison/bin/bison"
echo "QMAKE_YACC=$BISON_PATH" >> src/gcconfig.pri

# Enable compress library
echo "LIBZ_LIBS = -lz" >> src/gcconfig.pri

# GSL
GSL_PATH="$BREW_PREFIX/opt/gsl"
sed -i "" "s|#GSL_INCLUDES =.*|GSL_INCLUDES = ${GSL_PATH}/include|" src/gcconfig.pri
sed -i "" "s|#GSL_LIBS =.*|GSL_LIBS = -L${GSL_PATH}/lib -lgsl -lgslcblas -lm|" src/gcconfig.pri

# Define GC version string for tagged builds
if [ -n "$GITHUB_REF_NAME" ] && [[ "$GITHUB_REF_TYPE" == "tag" ]]; then
    echo "DEFINES += \"GC_VERSION=$GITHUB_REF_NAME\"" >> src/gcconfig.pri
fi

sed -i "" "s|#QMAKE_MOVE = cp|QMAKE_MOVE = cp|" src/gcconfig.pri
sed -i "" "s|#\(CONFIG += release.*\)|\1 static |" src/gcconfig.pri
sed -i "" "s|^#CloudDB|CloudDB|" src/gcconfig.pri
sed -i "" "s|^#LIBZ|LIBZ|" src/gcconfig.pri

# SRMIO
sed -i "" "s|#\(SRMIO_INSTALL =.*\)|\1 /usr/local|" src/gcconfig.pri

# D2XX
# Update D2XX.cpp to look for dylib in Frameworks (relative to executable)
sed -i "" "s|libftd2xx.dylib|@executable_path/../Frameworks/libftd2xx.1.4.24.dylib|" src/FileIO/D2XX.cpp
sed -i "" "s|#\(D2XX_INCLUDE =.*\)|\1 ../D2XX|" src/gcconfig.pri
sed -i "" "s|#\(D2XX_LIBS    =.*\)|\1 -L../D2XX -lftd2xx|" src/gcconfig.pri

# ICAL
ICAL_PATH="$BREW_PREFIX/opt/libical"
sed -i "" "s|#\(ICAL_INSTALL =.*\)|\1 ${ICAL_PATH}|" src/gcconfig.pri
sed -i "" "s|#\(ICAL_LIBS    =.*\)|\1 -L${ICAL_PATH}/lib -lical|" src/gcconfig.pri

# LIBUSB
LIBUSB_PATH="$BREW_PREFIX/opt/libusb"
sed -i "" "s|#\(LIBUSB_INSTALL =\).*|\1 ${LIBUSB_PATH}|" src/gcconfig.pri
sed -i "" "s|#\(LIBUSB_LIBS    =.*\)|\1 -L${LIBUSB_PATH}/lib -lusb-1.0|" src/gcconfig.pri
sed -i "" "s|#\(LIBUSB_USE_V_1 = true.*\)|\1|" src/gcconfig.pri

# SAMPLERATE
SAMPLERATE_PATH="$BREW_PREFIX/opt/libsamplerate"
sed -i "" "s|#\(SAMPLERATE_INSTALL =\).*|\1 ${SAMPLERATE_PATH}|" src/gcconfig.pri
sed -i "" "s|#\(SAMPLERATE_LIBS =\).*|\1 -L${SAMPLERATE_PATH}/lib -lsamplerate|" src/gcconfig.pri

# LMFIT
sed -i "" "s|#\(LMFIT_INSTALL =\).*|\1 /usr/local|" src/gcconfig.pri

sed -i "" "s|#\(DEFINES += GC_HAVE_LION*\)|\1|" src/gcconfig.pri

# HTTP Server
sed -i "" "s|#\(HTPATH = ../httpserver.*\)|\1 |" src/gcconfig.pri

# Robot
sed -i "" "s|#\(DEFINES += GC_WANT_ROBOT.*\)|\1 |" src/gcconfig.pri

# Qt6 VIDEO
sed -i "" "s|\(DEFINES += GC_VIDEO_NONE.*\)|#\1 |" src/gcconfig.pri
sed -i "" "s|#\(DEFINES += GC_VIDEO_QT6.*\)|\1 |" src/gcconfig.pri

# Enable R embedding
sed -i "" "s|#\(DEFINES += GC_WANT_R.*\)|\1 |" src/gcconfig.pri

# Python (avoiding collision between GC Context.h and Python context.h)
sed -i "" "s|#\(DEFINES += GC_WANT_PYTHON\)\.*|\1 |" src/gcconfig.pri

# TrainerDay Query API
echo "DEFINES += GC_WANT_TRAINERDAY_API" >> src/gcconfig.pri
echo "DEFINES += GC_TRAINERDAY_API_PAGESIZE=25" >> src/gcconfig.pri

# macOS version config
# Removing old architectire flags to allow native build on ARM
# echo "QMAKE_CXXFLAGS += -mmacosx-version-min=10.7 -arch x86_64" >> src/gcconfig.pri
# echo "QMAKE_CFLAGS_RELEASE += -mmacosx-version-min=10.7 -arch x86_64" >> src/gcconfig.pri
echo "QMAKE_MACOSX_DEPLOYMENT_TARGET = 11.0" >> src/gcconfig.pri

cat src/gcconfig.pri

# Patch Secrets.h with environment variables
# Note: In GHA, we use environment variables mapped from secrets.
# We will use a small inline python script or sed to replace placeholders.
# The AppVeyor script used PowerShell for this. We can use sed.

sed -i "" "s|__GC_GOOGLE_CALENDAR_CLIENT_SECRET__|${GC_GOOGLE_CALENDAR_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_GOOGLE_DRIVE_CLIENT_ID__|${GC_GOOGLE_DRIVE_CLIENT_ID}|" src/Core/Secrets.h
sed -i "" "s|__GC_GOOGLE_DRIVE_CLIENT_SECRET__|${GC_GOOGLE_DRIVE_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_GOOGLE_DRIVE_API_KEY__|${GC_GOOGLE_DRIVE_API_KEY}|" src/Core/Secrets.h
sed -i "" "s|OPENDATA_DISABLE|OPENDATA_ENABLE|" src/Core/Secrets.h
sed -i "" "s|__GC_CLOUD_OPENDATA_SECRET__|${GC_CLOUD_OPENDATA_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_WITHINGS_CONSUMER_SECRET__|${GC_WITHINGS_CONSUMER_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_NOKIA_CLIENT_SECRET__|${GC_NOKIA_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_DROPBOX_CLIENT_SECRET__|${GC_DROPBOX_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_STRAVA_CLIENT_SECRET__|${GC_STRAVA_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_CYCLINGANALYTICS_CLIENT_SECRET__|${GC_CYCLINGANALYTICS_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_CLOUD_DB_BASIC_AUTH__|${GC_CLOUD_DB_BASIC_AUTH}|" src/Core/Secrets.h
sed -i "" "s|__GC_CLOUD_DB_APP_NAME__|${GC_CLOUD_DB_APP_NAME}|" src/Core/Secrets.h
sed -i "" "s|__GC_POLARFLOW_CLIENT_SECRET__|${GC_POLARFLOW_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_SPORTTRACKS_CLIENT_SECRET__|${GC_SPORTTRACKS_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_RWGPS_API_KEY__|${GC_RWGPS_API_KEY}|" src/Core/Secrets.h
sed -i "" "s|__GC_NOLIO_CLIENT_ID__|${GC_NOLIO_CLIENT_ID}|" src/Core/Secrets.h
sed -i "" "s|__GC_NOLIO_SECRET__|${GC_NOLIO_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_XERT_CLIENT_SECRET__|${GC_XERT_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_AZUM_CLIENT_SECRET__|${GC_AZUM_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "" "s|__GC_TRAINERDAY_API_KEY__|${GC_TRAINERDAY_API_KEY}|" src/Core/Secrets.h

# Update translations
lupdate src/src.pro
