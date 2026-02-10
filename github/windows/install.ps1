# Windows Install Script
$ErrorActionPreference = "Stop"

# Create libs directory
New-Item -ItemType Directory -Force -Path "C:\libs"

# Install libraries via vcpkg
# vcpkg is pre-installed on GitHub Actions Windows runners
# We need to integrate it or just use the toolchain file?
# AppVeyor script: vcpkg install gsl:x64-windows
vcpkg install gsl:x64-windows
vcpkg install openssl:x64-windows

# Download libraries (gc-ci-libs.zip) from GitHub Releases if not present
# Download libraries (gc-ci-libs.zip) from GitHub Releases if not present
# Check if destination exists
if (-not (Test-Path "C:\libs\include")) {
    $libsUrl = "https://github.com/GoldenCheetah/WindowsSDK/releases/download/v0.1.1/gc-ci-libs.zip"
    $libsFile = "gc-ci-libs.zip"
    Invoke-WebRequest -Uri $libsUrl -OutFile $libsFile
    7z x -y $libsFile -oC:\libs
}
else {
    Write-Host "Libs cached at C:\libs"
}

# Install jom
if (-not (Test-Path "C:\jom\jom.exe")) {
    $jomUrl = "https://download.qt.io/official_releases/jom/jom_1_1_3.zip"
    $jomFile = "jom_1_1_3.zip"
    Invoke-WebRequest -Uri $jomUrl -OutFile $jomFile
    7z x -y $jomFile -oc:\jom
}
else {
    Write-Host "Jom cached at C:\jom"
}
# Add jom to PATH
echo "C:\jom" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append

# R Installation
if (-not (Test-Path 'C:\R\bin\R.exe')) {
    $rurl = "https://cran.r-project.org/bin/windows/base/old/4.1.3/R-4.1.3-win.exe"
    Invoke-WebRequest -Uri $rurl -OutFile "R-win.exe"
    Start-Process -FilePath .\R-win.exe -ArgumentList "/VERYSILENT /DIR=C:\R" -NoNewWindow -Wait
}
else {
    Write-Host "R cached at C:\R"
}
echo "C:\R\bin" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append

# Python Embedding
# Check C:\Python\python.exe (Corrected path)
if (-not (Test-Path 'C:\Python\python.exe')) {
    $pyurl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
    Invoke-WebRequest -Uri $pyurl -OutFile "python-embed.zip"
    Expand-Archive -Path python-embed.zip -DestinationPath C:\Python -Force

    # Enable pip in embedded Python
    $pthFile = "C:\Python\python311._pth"
    (Get-Content $pthFile) -replace '#import site', 'import site' | Set-Content $pthFile

    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "get-pip.py"
    & C:\Python\python.exe get-pip.py --no-warn-script-location
}
else {
    Write-Host "Python cached at C:\Python"
}
echo "C:\Python" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
echo "C:\Python\Scripts" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append

# Install Python requirements into Embeddable Python (for packaging)
# Pip will skip satisfied requirements
& C:\Python\python.exe -m pip install --upgrade pip
& C:\Python\python.exe -m pip install --only-binary :all: -r src/Python/requirements.txt

# Install Python requirements into System Python (for build/SIP)
# This is the python set up by setup-python action
python -m pip install --upgrade pip
python -m pip install --only-binary :all: -r src/Python/requirements.txt
