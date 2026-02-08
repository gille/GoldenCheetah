# Windows Before Build Script
$ErrorActionPreference = "Stop"

# Config copies
Copy-Item "qwt\qwtconfig.pri.in" "qwt\qwtconfig.pri"
if (Test-Path "C:\libs\gcconfig64Qt6-Release.appveyor.pri") {
    Copy-Item "C:\libs\gcconfig64Qt6-Release.appveyor.pri" "src\gcconfig.pri"
} else {
    Copy-Item "src\gcconfig.pri.in" "src\gcconfig.pri"
}

$gcconfig = "src\gcconfig.pri"

# Function to replace text in a file
function Replace-InFile {
    param ([string]$File, [string]$Pattern, [string]$Replacement)
    (Get-Content $File) -replace $Pattern, $Replacement | Set-Content $File
}

function Add-Config {
    param([string]$line)
    $line | Out-File -FilePath $gcconfig -Encoding utf8 -Append
}

# 1. App Name
Add-Config "APP_NAME = GoldenCheetah"

# 2. Config Release
Add-Config "CONFIG += release"

# 3. Disable strerror deprecation warning
Add-Config "DEFINES += _CRT_SECURE_NO_WARNINGS"

# 4. lrelease
Add-Config "QMAKE_LRELEASE = lrelease"

# 5. Lex/Yacc
Add-Config "CONFIG += lex"
Add-Config "CONFIG += yacc"
Add-Config "QMAKE_LEX  = c:\libs\win_flex --wincompat"
Add-Config "QMAKE_YACC = c:\libs\win_bison --file-prefix=y -t"

Add-Config "lex.CONFIG += target_predeps"
Add-Config "yacc_impl.CONFIG += target_predeps"
Add-Config "yacc_decl.CONFIG += target_predeps"

# 6. D2XX
Add-Config "D2XX_INCLUDE = c:\libs\10_Precompiled_DLL\D2XX\CDM"
Add-Config "D2XX_LIBS = -Lc:\libs\10_Precompiled_DLL\D2XX\CDM\Static\amd64 -lftd2xx"

# 7. ICAL
Add-Config "ICAL_INSTALL = c:\libs\10_Precompiled_DLL\libical64"
Add-Config "ICAL_INCLUDE = c:\libs\10_Precompiled_DLL\libical64\include"
Add-Config "ICAL_LIBS = -Lc:\libs\10_Precompiled_DLL\libical64\lib-release -llibical-static"

# 8. USBXPRESS
Add-Config "USBXPRESS_INSTALL = c:\libs\10_Precompiled_DLL\usbexpress_3.5.1\USBXpress\USBXpress_API\Host"
Add-Config "USBXPRESS_INCLUDE = c:\libs\10_Precompiled_DLL\usbexpress_3.5.1\USBXpress\USBXpress_API\Host"
Add-Config "USBXPRESS_LIBS = -Lc:\libs\10_Precompiled_DLL\usbexpress_3.5.1\USBXpress\USBXpress_API\Host\x64 -lSiUSBXp"

# 9. LIBUSB
Add-Config "LIBUSB_INSTALL = c:\libs\10_Precompiled_DLL\libusb-win32-bin-1.2.6.0"
Add-Config "LIBUSB_INCLUDE = c:\libs\10_Precompiled_DLL\libusb-win32-bin-1.2.6.0\include"
Add-Config "LIBUSB_LIBS = -Lc:\libs\10_Precompiled_DLL\libusb-win32-bin-1.2.6.0\lib\msvc_x64 -llibusb"

# 10. SAMPLERATE
Add-Config "SAMPLERATE_INSTALL = c:\libs\10_Precompiled_DLL\libsamplerate64"
Add-Config "SAMPLERATE_INCLUDE = c:\libs\10_Precompiled_DLL\libsamplerate64\include"
Add-Config "SAMPLERATE_LIBS = -Lc:\libs\10_Precompiled_DLL\libsamplerate64\lib -llibsamplerate-0"

# 11. HTPATH
Add-Config "HTPATH = ../httpserver"

# 12. Video
# Disable NONE, Enable QT6
Add-Config "DEFINES -= GC_VIDEO_NONE"
Add-Config "DEFINES += GC_VIDEO_QT6"

# 13. R Support
Add-Config "DEFINES += GC_WANT_R"

# 14. Python Support
# Detect from active system/setup-python
# GitHub Actions setup-python sets 'pythonLocation' environment variable
if ($env:pythonLocation) {
    Write-Host "Detected setup-python environment at $env:pythonLocation"
    $pyBase = $env:pythonLocation
    $pyInc = "$pyBase\include"
    $pyLib = "$pyBase\libs"
} else {
    # Fallback to sysconfig detection
    $pyInc = python -c "import sysconfig; print(sysconfig.get_path('include'))"
    $pyLib = python -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))"
}

# Clean whitespace
if ($pyInc) { $pyInc = $pyInc.Trim() }
if ($pyLib) { $pyLib = $pyLib.Trim() }

# Debug info
Write-Host "Python Include via sysconfig: $pyInc"
if (Test-Path "$pyInc\Python.h") {
    Write-Host "Found Python.h in $pyInc"
} else {
    Write-Host "WARNING: Python.h NOT FOUND in $pyInc"
    # Fallback: Search in sys.prefix
    $prefix = python -c "import sys; print(sys.prefix)"
    $prefix = $prefix.Trim()
    Write-Host "Searching for Python.h in $prefix..."
    $found = Get-ChildItem -Path $prefix -Filter "Python.h" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $pyInc = $found.DirectoryName
        Write-Host "FOUND Python.h at $pyInc"
    } else {
        Write-Host "ERROR: Python.h could not be found anywhere under $prefix"
    }
}

# Handle fallback for libs
if (-not $pyLib -or $pyLib -eq "None") {
    $prefix = python -c "import sys; print(sys.prefix)"
    $pyLib = "$prefix\libs"
}

# Normalize to forward slashes for QMake and robustness
$pyInc = $pyInc -replace '\\', '/'
$pyLib = $pyLib -replace '\\', '/'

Add-Config "DEFINES += GC_WANT_PYTHON"
# AppVeyor had -ICore, so we add it. GHA paths might have spaces, so we quote.
Add-Config "PYTHONINCLUDES = -ICore -I`"$pyInc`""
Add-Config "PYTHONLIBS = -L`"$pyLib`" -lpython311"

# 15. GSL Support
# GHA Windows runner usually has vcpkg at C:\vcpkg or in VCPKG_INSTALLATION_ROOT
$vcpkgRoot = "C:\vcpkg"
if ($env:VCPKG_INSTALLATION_ROOT) {
    $vcpkgRoot = $env:VCPKG_INSTALLATION_ROOT
}
$vcpkgRoot = $vcpkgRoot -replace '\\', '/'

Add-Config "GSL_INCLUDES = $vcpkgRoot/installed/x64-windows/include"
Add-Config "GSL_LIBS = -L$vcpkgRoot/installed/x64-windows/lib -lgsl -lgslcblas"

# 16. CloudDB
Add-Config "CloudDB = active"

# 17. Train Robot
Add-Config "DEFINES += GC_WANT_ROBOT"

# 18. TrainerDay
Add-Config "DEFINES += GC_WANT_TRAINERDAY_API"
Add-Config "DEFINES += GC_TRAINERDAY_API_PAGESIZE=25"

# 19. Math & Nominmax
Add-Config "DEFINES += _MATH_DEFINES_DEFINED"
Add-Config "DEFINES += NOMINMAX"

# Tag Version
if ($env:GITHUB_REF_TYPE -eq 'tag') {
    Add-Config "DEFINES+=GC_VERSION=$env:GITHUB_REF_NAME"
}

# Secrets Patching
$secretsFile = "src\Core\Secrets.h"
function Patch-Secret {
    param([string]$placeholder, [string]$value)
    if (-not $value) { return }
    (Get-Content $secretsFile) -replace $placeholder, $value | Set-Content $secretsFile
}

Patch-Secret '__GC_GOOGLE_CALENDAR_CLIENT_SECRET__' $env:GC_GOOGLE_CALENDAR_CLIENT_SECRET
Patch-Secret '__GC_GOOGLE_DRIVE_CLIENT_ID__' $env:GC_GOOGLE_DRIVE_CLIENT_ID
Patch-Secret '__GC_GOOGLE_DRIVE_CLIENT_SECRET__' $env:GC_GOOGLE_DRIVE_CLIENT_SECRET
Patch-Secret '__GC_GOOGLE_DRIVE_API_KEY__' $env:GC_GOOGLE_DRIVE_API_KEY
Patch-Secret 'OPENDATA_DISABLE' 'OPENDATA_ENABLE'
Patch-Secret '__GC_CLOUD_OPENDATA_SECRET__' $env:GC_CLOUD_OPENDATA_SECRET
Patch-Secret '__GC_WITHINGS_CONSUMER_SECRET__' $env:GC_WITHINGS_CONSUMER_SECRET
Patch-Secret '__GC_NOKIA_CLIENT_SECRET__' $env:GC_NOKIA_CLIENT_SECRET
Patch-Secret '__GC_DROPBOX_CLIENT_SECRET__' $env:GC_DROPBOX_CLIENT_SECRET
Patch-Secret '__GC_STRAVA_CLIENT_SECRET__' $env:GC_STRAVA_CLIENT_SECRET
Patch-Secret '__GC_CYCLINGANALYTICS_CLIENT_SECRET__' $env:GC_CYCLINGANALYTICS_CLIENT_SECRET
Patch-Secret '__GC_CLOUD_DB_BASIC_AUTH__' $env:GC_CLOUD_DB_BASIC_AUTH
Patch-Secret '__GC_CLOUD_DB_APP_NAME__' $env:GC_CLOUD_DB_APP_NAME
Patch-Secret '__GC_POLARFLOW_CLIENT_SECRET__' $env:GC_POLARFLOW_CLIENT_SECRET
Patch-Secret '__GC_SPORTTRACKS_CLIENT_SECRET__' $env:GC_SPORTTRACKS_CLIENT_SECRET
Patch-Secret '__GC_RWGPS_API_KEY__' $env:GC_RWGPS_API_KEY
Patch-Secret '__GC_NOLIO_CLIENT_ID__' $env:GC_NOLIO_CLIENT_ID
Patch-Secret '__GC_NOLIO_SECRET__' $env:GC_NOLIO_SECRET
Patch-Secret '__GC_XERT_CLIENT_SECRET__' $env:GC_XERT_CLIENT_SECRET
Patch-Secret '__GC_AZUM_CLIENT_SECRET__' $env:GC_AZUM_CLIENT_SECRET
Patch-Secret '__GC_TRAINERDAY_API_KEY__' $env:GC_TRAINERDAY_API_KEY

# Update translations
lupdate src\src.pro
