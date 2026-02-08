#!/bin/bash
set -ev

# Helper: gh release download wrapper
gh_download() {
    local repo="$1"
    local tag="$2"
    local pattern="$3"
    local output="$4"
    
    echo "Downloading $pattern from $repo ($tag)..."
    gh release download "$tag" -D . -p "$pattern" --repo "$repo" --clobber
    
    if [ ! -f "$pattern" ]; then
        echo "Failed to download $pattern"
        exit 1
    fi
    
    # Rename if output name is different (gh downloads with original name)
    if [ "$pattern" != "$output" ]; then
        mv "$pattern" "$output"
    fi
}

### Download linuxdeployqt
gh_download "probonopd/linuxdeployqt" "continuous" "linuxdeployqt-continuous-x86_64.AppImage" "linuxdeployqt-continuous-x86_64.AppImage"
chmod a+x linuxdeployqt-continuous-x86_64.AppImage

### Deploy to appdir (but don't build AppImage yet)
./linuxdeployqt-continuous-x86_64.AppImage appdir/GoldenCheetah -verbose=2 -bundle-non-qt-libs -exclude-libs=libqsqlmysql,libqsqlpsql,libqsqlmimer,libqsqlodbc,libnss3,libnssutil3,libxcb-dri3.so.0 -unsupported-allow-new-glibc

# Add Python and core modules (AppVeyor Logic)
# Construct filename: python3.11.14-cp311-cp311-manylinux_2_28_x86_64.AppImage
# remove dots from version for cp part
VER_NODOTS="${PYTHON_VERSION//./}"
PYTHON_APPIMAGE_FILE="python${PYTHON_APPIMAGE_VERSION}-cp${VER_NODOTS}-cp${VER_NODOTS}-manylinux_2_28_x86_64.AppImage"

echo "Downloading Python AppImage: $PYTHON_APPIMAGE_FILE"
mkdir -p python_bundle
pushd python_bundle

gh_download "niess/python-appimage" "python${PYTHON_VERSION}" "${PYTHON_APPIMAGE_FILE}" "${PYTHON_APPIMAGE_FILE}"
chmod +x "${PYTHON_APPIMAGE_FILE}"
./"${PYTHON_APPIMAGE_FILE}" --appimage-extract
rm -f "${PYTHON_APPIMAGE_FILE}"

# Install requirements into this isolated python
export PATH="$(pwd)/squashfs-root/usr/bin:$PATH"
pip install --upgrade pip
pip install -q -r ../Python/requirements.txt

# Move to AppDir
mv squashfs-root/usr ../appdir/usr
mv squashfs-root/opt ../appdir/opt
popd
rm -rf python_bundle

# Fix RPATH on QtWebEngineProcess
if [ -f "appdir/libexec/QtWebEngineProcess" ]; then
    patchelf --set-rpath '$ORIGIN/../lib' appdir/libexec/QtWebEngineProcess
fi

# Copy Qt Resources
QT_INSTALL_PREFIX=$(qmake -query QT_INSTALL_PREFIX 2>/dev/null || echo "")
if [ -n "$QT_INSTALL_PREFIX" ] && [ -d "${QT_INSTALL_PREFIX}/resources" ]; then
    cp -r "${QT_INSTALL_PREFIX}/resources" appdir/
else
    echo "Warning: Could not find Qt resources directory"
fi

# Generate AppImage

gh_download "AppImage/appimagetool" "continuous" "appimagetool-x86_64.AppImage" "appimagetool-x86_64.AppImage"
chmod a+x appimagetool-x86_64.AppImage

# Set ARCH explicitly? appimagetool usually finds it.
./appimagetool-x86_64.AppImage appdir

### Cleanup
rm linuxdeployqt-continuous-x86_64.AppImage
rm appimagetool-x86_64.AppImage
rm -rf appdir

# Expect output
if [ ! -f GoldenCheetah*.AppImage ]; then
    echo "AppImage not generated, check the errors"
    exit 1
fi

echo "Renaming AppImage file..."
mv GoldenCheetah*.AppImage ../GoldenCheetah_v3.8_x64.AppImage
