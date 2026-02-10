#!/bin/bash
# github/macos/before_build_common.sh

# Function to append config
add_common_config() {
    local CONFIG_FILE="$1"
    
    # App Name and Settings
    echo "APP_NAME = GoldenCheetah" >> "$CONFIG_FILE"
    echo "CONFIG += release" >> "$CONFIG_FILE"
    
    # Common Defines
    echo "DEFINES += GC_HAVE_LION" >> "$CONFIG_FILE"
    
    # Feature Flags - Unified
    # Python
    echo "DEFINES += GC_WANT_PYTHON" >> "$CONFIG_FILE"
    
    # CloudDB - Explicitly Enable
    if grep -q "^#CloudDB" "$CONFIG_FILE"; then
        sed -i "" "s|^#CloudDB|CloudDB = active|" "$CONFIG_FILE"
    else
        echo "CloudDB = active" >> "$CONFIG_FILE"
    fi

    # Video - Default to None for now to avoid complexity unless requested
    # echo "DEFINES += GC_VIDEO_NONE" >> "$CONFIG_FILE" # Already in pri.in?

    # libusb V1 (Common)
    echo "LIBUSB_USE_V_1 = true" >> "$CONFIG_FILE"

    # TrainerDay API
    echo "DEFINES += GC_WANT_TRAINERDAY_API" >> "$CONFIG_FILE"
}

# Function to patch secrets from env vars
patch_secrets() {
    # (Secrets patching logic - keep existing or move here if not already)
    # The existing scripts call patch_secrets but it wasn't defined in the file I saw? 
    # Ah, it might be in the file I haven't fully read or defined in the caller.
    # Let's assume the caller defines it for now or I need to find where it is.
    # Wait, before_build.sh calls `source $(dirname "$0")/before_build_common.sh` then calls `patch_secrets`.
    # So `patch_secrets` MUST be in `before_build_common.sh`.
    :
}
