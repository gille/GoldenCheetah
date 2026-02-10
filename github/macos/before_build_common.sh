#!/bin/bash

# Common functions for macOS build configuration

# Function to patch Secrets.h with environment variables
patch_secrets() {
    local secrets_file="src/Core/Secrets.h"
    echo "Patching secrets in $secrets_file..."

    # helper for sed in-place on macOS
    sed_i() {
        sed -i '' "$@"
    }

    sed_i "s|__GC_GOOGLE_CALENDAR_CLIENT_SECRET__|$GC_GOOGLE_CALENDAR_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_GOOGLE_DRIVE_CLIENT_ID__|$GC_GOOGLE_DRIVE_CLIENT_ID|g" "$secrets_file"
    sed_i "s|__GC_GOOGLE_DRIVE_CLIENT_SECRET__|$GC_GOOGLE_DRIVE_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_GOOGLE_DRIVE_API_KEY__|$GC_GOOGLE_DRIVE_API_KEY|g" "$secrets_file"
    sed_i "s|OPENDATA_DISABLE|OPENDATA_ENABLE|g" "$secrets_file"
    sed_i "s|__GC_CLOUD_OPENDATA_SECRET__|$GC_CLOUD_OPENDATA_SECRET|g" "$secrets_file"
    sed_i "s|__GC_WITHINGS_CONSUMER_SECRET__|$GC_WITHINGS_CONSUMER_SECRET|g" "$secrets_file"
    sed_i "s|__GC_NOKIA_CLIENT_SECRET__|$GC_NOKIA_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_DROPBOX_CLIENT_SECRET__|$GC_DROPBOX_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_STRAVA_CLIENT_SECRET__|$GC_STRAVA_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_CYCLINGANALYTICS_CLIENT_SECRET__|$GC_CYCLINGANALYTICS_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_CLOUD_DB_BASIC_AUTH__|$GC_CLOUD_DB_BASIC_AUTH|g" "$secrets_file"
    sed_i "s|__GC_CLOUD_DB_APP_NAME__|$GC_CLOUD_DB_APP_NAME|g" "$secrets_file"
    sed_i "s|__GC_POLARFLOW_CLIENT_SECRET__|$GC_POLARFLOW_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_SPORTTRACKS_CLIENT_SECRET__|$GC_SPORTTRACKS_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_RWGPS_API_KEY__|$GC_RWGPS_API_KEY|g" "$secrets_file"
    sed_i "s|__GC_NOLIO_CLIENT_ID__|$GC_NOLIO_CLIENT_ID|g" "$secrets_file"
    sed_i "s|__GC_NOLIO_SECRET__|$GC_NOLIO_SECRET|g" "$secrets_file"
    sed_i "s|__GC_XERT_CLIENT_SECRET__|$GC_XERT_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_AZUM_CLIENT_SECRET__|$GC_AZUM_CLIENT_SECRET|g" "$secrets_file"
    sed_i "s|__GC_TRAINERDAY_API_KEY__|$GC_TRAINERDAY_API_KEY|g" "$secrets_file"
}

# Function to apply common configuration to a file
# usage: add_common_config <config_file>
add_common_config() {
    local config_file="$1"

    echo "Applying common config to $config_file..."

    # helper for sed in-place on macOS
    sed_i() {
        sed -i '' "$@"
    }

    # App Name
    sed_i "s|#APP_NAME =|APP_NAME = GoldenCheetah|" "$config_file"

    # Release mode
    sed_i "s|#CONFIG += release|CONFIG += release|" "$config_file"

    # Common Defines
    # HTPATH
    sed_i "s|#HTPATH = ../httpserver|HTPATH = ../httpserver|" "$config_file"

    # Video
    sed_i "s|DEFINES += GC_VIDEO_NONE|#DEFINES += GC_VIDEO_NONE|" "$config_file"
    sed_i "s|#DEFINES += GC_VIDEO_QT6|DEFINES += GC_VIDEO_QT6|" "$config_file"

    # R
    sed_i "s|#DEFINES += GC_WANT_R|DEFINES += GC_WANT_R|" "$config_file"

    # Robot
    sed_i "s|#DEFINES += GC_WANT_ROBOT|DEFINES += GC_WANT_ROBOT|" "$config_file"

    # Python (Feature enable)
    sed_i "s|#DEFINES += GC_WANT_PYTHON|DEFINES += GC_WANT_PYTHON|" "$config_file"

    # LibUSB v1 (Feature enable)
    sed_i "s|#LIBUSB_USE_V_1 = true.*|LIBUSB_USE_V_1 = true|" "$config_file"

    # TrainerDay (Common)
    sed_i "s|#DEFINES += GC_WANT_TRAINERDAY_API|DEFINES += GC_WANT_TRAINERDAY_API|" "$config_file"
    # Note: there is no placeholder for pagesize? Checking pri.in... line 308
    sed_i "s|#DEFINES += GC_TRAINERDAY_API_PAGESIZE=25|DEFINES += GC_TRAINERDAY_API_PAGESIZE=25|" "$config_file"
}
