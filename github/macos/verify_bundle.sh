#!/bin/bash
# verify_bundle.sh
# Verifies that GoldenCheetah.app does not link against system/homebrew libraries.

APP_BUNDLE="${1:-src/GoldenCheetah.app}"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: Bundle not found at $APP_BUNDLE"
    exit 1
fi

echo "Verifying bundle at $APP_BUNDLE..."
echo "Scanning for dependencies linking to /usr/local, /opt/homebrew, or /Users..."

FOUND_LEAKS=0

# Find all Mach-O files (executables, dylibs, so bundles)
# We use 'file' to identify Mach-O binaries to avoid scanning scripts/text files
while read FILE; do
    if file "$FILE" | grep -q "Mach-O"; then
        # Check dependencies
        LEAKS=$(otool -L "$FILE" | grep -E "(/usr/local/|/opt/homebrew/|/Users/|/Library/Frameworks/)" | grep -v "/System/")

        if [ -n "$LEAKS" ]; then
            echo "---------------------------------------------------"
            echo "LEAK FOUND in: $FILE"
            echo "$LEAKS"
            FOUND_LEAKS=1
        fi
    fi
done < <(find "$APP_BUNDLE" -type f)

if [ "$FOUND_LEAKS" -eq 1 ]; then
    echo "---------------------------------------------------"
    echo "VERIFICATION FAILED: The bundle is linking against system libraries."
    exit 1
else
    echo "---------------------------------------------------"
    echo "VERIFICATION PASSED: No system library leaks detected."
    exit 0
fi
