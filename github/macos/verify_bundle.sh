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
        # Skip the first line (the file path itself) and filter for system paths
        # We also filter out lines ending in ":" because otool prints the binary path as a header for each arch
        LEAKS=$(otool -L "$FILE" | grep -v ":$" | grep -E "(/usr/local/|/opt/homebrew/|/Users/|/Library/Frameworks/|/opt/local/)" | grep -v "/System/")

        if [ -n "$LEAKS" ]; then
            echo "---------------------------------------------------"
            echo "LEAK FOUND in: $FILE"
            echo "$LEAKS"
            FOUND_LEAKS=1
        fi

        # Check for broken @rpath links (referenced lib missing from bundle)
        # We assume @rpath maps to Contents/Frameworks for most libs
        otool -L "$FILE" | grep "@rpath/" | awk '{print $1}' | while read RPATH_LIB; do
            LIB_NAME=$(basename "$RPATH_LIB")
            # Ignore self-references (rare, but possible) or system frameworks checked by rpath?
            # Standard check: is it in Frameworks?
            # Check if the RPATH points into a framework
            if [[ "$RPATH_LIB" == *".framework/"* ]]; then
                # RPATH_LIB might be @rpath/Foo.framework/Versions/A/Foo
                # We check if Foo.framework exists in Frameworks
                # Extract just the framework name part (Foo.framework)
                FRAMEWORK_NAME=$(echo "$RPATH_LIB" | grep -o "[^/]*\.framework")
                
                if [ ! -d "$APP_BUNDLE/Contents/Frameworks/$FRAMEWORK_NAME" ]; then
                        echo "---------------------------------------------------"
                        echo "MISSING RPATH FRAMEWORK in: $FILE"
                        echo "  Referenced: $RPATH_LIB"
                        echo "  Missing at: $APP_BUNDLE/Contents/Frameworks/$FRAMEWORK_NAME"
                        FOUND_LEAKS=1
                fi
            else
                # Ordinary dylib
                # Standard check: is it in Frameworks?
                if [ ! -f "$APP_BUNDLE/Contents/Frameworks/$LIB_NAME" ] && [ ! -f "$APP_BUNDLE/Contents/PlugIns/$LIB_NAME" ]; then
                        echo "---------------------------------------------------"
                        echo "MISSING RPATH LIB in: $FILE"
                        echo "  Referenced: $RPATH_LIB"
                        echo "  Missing at: $APP_BUNDLE/Contents/Frameworks/$LIB_NAME"
                        FOUND_LEAKS=1
                fi
            fi
        done
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
