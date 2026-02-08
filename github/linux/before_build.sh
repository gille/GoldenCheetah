#!/bin/bash
set -ev

cp qwt/qwtconfig.pri.in qwt/qwtconfig.pri
cp src/gcconfig.pri.in src/gcconfig.pri

# Helper to add to gcconfig.pri
add_config() {
    echo "$1" >> src/gcconfig.pri
}

add_config "QMAKE_YACC = bison"
add_config "LIBZ_LIBS = -lz"
add_config "GSL_INCLUDES = /usr/include"
add_config "GSL_LIBS = -lgsl -lgslcblas -lm"

if [ -n "$GITHUB_REF_NAME" ] && [[ "$GITHUB_REF_TYPE" == "tag" ]]; then
    add_config "DEFINES += \"GC_VERSION=$GITHUB_REF_NAME\""
fi

sed -i "s|#QMAKE_MOVE = cp|QMAKE_MOVE = cp|" src/gcconfig.pri
sed -i "s|#\(CONFIG += release.*\)|\1 static |" src/gcconfig.pri
sed -i "s|^#CloudDB|CloudDB|" src/gcconfig.pri
sed -i "s|^#LIBZ|LIBZ|" src/gcconfig.pri

# Libraries
add_config "ICAL_INSTALL = /usr"
add_config "ICAL_LIBS = -lical"
add_config "LIBUSB_INSTALL = /usr"
add_config "LIBUSB_LIBS = -lusb-1.0 -ldl -ludev"
# Use libusb-1.0 API instead of legacy usb.h
add_config "LIBUSB_USE_V_1 = true"
add_config "SAMPLERATE_INSTALL = /usr"
add_config "SAMPLERATE_LIBS = -lsamplerate"
add_config "D2XX_INCLUDE = ../D2XX/release"
add_config "SRMIO_INSTALL = /usr/local"

sed -i "s|#\(DEFINES += GC_WANT_ROBOT.*\)|\1 |" src/gcconfig.pri
sed -i "s|\(DEFINES += GC_VIDEO_NONE.*\)|#\1 |" src/gcconfig.pri
sed -i "s|#\(DEFINES += GC_VIDEO_QT6.*\)|\1 |" src/gcconfig.pri
sed -i "s|#\(DEFINES += GC_WANT_R.*\)|\1 |" src/gcconfig.pri
sed -i "s|^#HTPATH|HTPATH|" src/gcconfig.pri
sed -i "s|#\(DEFINES += GC_WANT_PYTHON\)\.*|\1 |" src/gcconfig.pri

add_config "DEFINES += GC_WANT_TRAINERDAY_API"
add_config "DEFINES += GC_TRAINERDAY_API_PAGESIZE=25"

# Secrets Patching
sed -i "s|__GC_GOOGLE_CALENDAR_CLIENT_SECRET__|${GC_GOOGLE_CALENDAR_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_GOOGLE_DRIVE_CLIENT_ID__|${GC_GOOGLE_DRIVE_CLIENT_ID}|" src/Core/Secrets.h
sed -i "s|__GC_GOOGLE_DRIVE_CLIENT_SECRET__|${GC_GOOGLE_DRIVE_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_GOOGLE_DRIVE_API_KEY__|${GC_GOOGLE_DRIVE_API_KEY}|" src/Core/Secrets.h
sed -i "s|OPENDATA_DISABLE|OPENDATA_ENABLE|" src/Core/Secrets.h
sed -i "s|__GC_CLOUD_OPENDATA_SECRET__|${GC_CLOUD_OPENDATA_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_WITHINGS_CONSUMER_SECRET__|${GC_WITHINGS_CONSUMER_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_NOKIA_CLIENT_SECRET__|${GC_NOKIA_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_DROPBOX_CLIENT_SECRET__|${GC_DROPBOX_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_STRAVA_CLIENT_SECRET__|${GC_STRAVA_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_CYCLINGANALYTICS_CLIENT_SECRET__|${GC_CYCLINGANALYTICS_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_CLOUD_DB_BASIC_AUTH__|${GC_CLOUD_DB_BASIC_AUTH}|" src/Core/Secrets.h
sed -i "s|__GC_CLOUD_DB_APP_NAME__|${GC_CLOUD_DB_APP_NAME}|" src/Core/Secrets.h
sed -i "s|__GC_POLARFLOW_CLIENT_SECRET__|${GC_POLARFLOW_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_SPORTTRACKS_CLIENT_SECRET__|${GC_SPORTTRACKS_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_RWGPS_API_KEY__|${GC_RWGPS_API_KEY}|" src/Core/Secrets.h
sed -i "s|__GC_NOLIO_CLIENT_ID__|${GC_NOLIO_CLIENT_ID}|" src/Core/Secrets.h
sed -i "s|__GC_NOLIO_SECRET__|${GC_NOLIO_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_XERT_CLIENT_SECRET__|${GC_XERT_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_AZUM_CLIENT_SECRET__|${GC_AZUM_CLIENT_SECRET}|" src/Core/Secrets.h
sed -i "s|__GC_TRAINERDAY_API_KEY__|${GC_TRAINERDAY_API_KEY}|" src/Core/Secrets.h

lupdate src/src.pro
