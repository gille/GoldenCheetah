# Windows After Build Script
$ErrorActionPreference = "Stop"

Set-Location "src/release"

# Run windeployqt
windeployqt --release GoldenCheetah.exe

# Copy dependencies
# Resolve vcpkg root
$vcpkgRoot = "C:\vcpkg"
if ($env:VCPKG_INSTALLATION_ROOT) {
    $vcpkgRoot = $env:VCPKG_INSTALLATION_ROOT
}
Write-Host "Using vcpkg root: $vcpkgRoot"

# Copy dependencies
Copy-Item "c:\libs\10_Precompiled_DLL\usbexpress_3.5.1\USBXpress\USBXpress_API\Host\x64\SiUSBXp.dll" .
Copy-Item "c:\libs\10_Precompiled_DLL\libsamplerate64\lib\libsamplerate-0.dll" .

# OpenSSL
# Check vcpkg location first
if (Test-Path "$vcpkgRoot\installed\x64-windows\bin\libssl-3-x64.dll") {
    Write-Host "Found OpenSSL in vcpkg"
    Copy-Item "$vcpkgRoot\installed\x64-windows\bin\libssl*.dll" .
    Copy-Item "$vcpkgRoot\installed\x64-windows\bin\libcrypto*.dll" .
} elseif (Test-Path "C:\OpenSSL-Win64\bin\libssl-3-x64.dll") {
    Write-Host "Found OpenSSL in C:\OpenSSL-Win64"
    Copy-Item "C:\OpenSSL-Win64\bin\lib*.dll" .
} else {
    Write-Host "WARNING: OpenSSL DLLs not found!"
    # List vcpkg bin to help debug
    if (Test-Path "$vcpkgRoot\installed\x64-windows\bin") {
        Get-ChildItem "$vcpkgRoot\installed\x64-windows\bin" | Select-Object Name
    }
}

# Copy Python
Copy-Item -Path "C:\Python" -Destination "." -Recurse -Force

# GSL DLLs
if (Test-Path "$vcpkgRoot\installed\x64-windows\bin\gsl.dll") {
    Copy-Item "$vcpkgRoot\installed\x64-windows\bin\gsl*.dll" .
} else {
    Write-Host "WARNING: GSL DLLs not found in $vcpkgRoot\installed\x64-windows\bin"
}

# ReadMe, license, ico
Copy-Item "..\Resources\win32\ReadMe.txt" .
"GoldenCheetah is licensed under the GNU General Public License v2" | Out-File "license.txt" -Encoding utf8
Get-Content "..\..\COPYING" | Out-File "license.txt" -Encoding utf8 -Append
Copy-Item "..\Resources\win32\gc.ico" .

# Build Installer
Copy-Item "..\Resources\win32\GC3.8-Master-W64-QT6.nsi" .

# Setup NSIS Path
$env:PATH += ";C:\Program Files (x86)\NSIS"
makensis GC3.8-Master-W64-QT6.nsi

# Move to root for artifact upload
Move-Item "GoldenCheetah_v3.8_64bit_Windows.exe" "..\..\GoldenCheetah_v3.8_x64.exe"

# Version check
Set-Location "..\.."
./GoldenCheetah_v3.8_x64.exe --version | Out-File "GCversionWindows.txt"
