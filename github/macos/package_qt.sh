#!/bin/bash
set -e

# github/macos/package_qt.sh
# Usage: ./package_qt.sh <AppBundlePath>
# Example: ./package_qt.sh GoldenCheetah.app

APP_BUNDLE="$1"

if [ -z "$APP_BUNDLE" ]; then
    echo "Usage: $0 <AppBundlePath>"
    exit 1
fi

echo "=== Shared Qt Packaging: macdeployqt & Cleanup ==="
echo "Bundle: $APP_BUNDLE"

# 1. Run macdeployqt
echo "Running macdeployqt..."
# We use macdeployqt to bundle Qt frameworks and plugins
macdeployqt "$APP_BUNDLE" -verbose=2 -executable="$APP_BUNDLE/Contents/MacOS/GoldenCheetah"

# 2. Cleanup Unused Plugins (Reduce Bundle Size & Dependencies)
echo "Cleaning up unused Qt plugins..."
# Remove SQL drivers if they exist (we don't use ODBC/PSQL usually, and they drag in dependencies like libiodbc)
rm -rf "$APP_BUNDLE/Contents/PlugIns/sqldrivers/libqsqlodbc.dylib"
rm -rf "$APP_BUNDLE/Contents/PlugIns/sqldrivers/libqsqlpsql.dylib"

echo "Qt Packaging Complete."
