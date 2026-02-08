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
$libsUrl = "https://github.com/GoldenCheetah/WindowsSDK/releases/download/v0.1.1/gc-ci-libs.zip"
$libsFile = "gc-ci-libs.zip"
if (-not (Test-Path $libsFile)) {
    Invoke-WebRequest -Uri $libsUrl -OutFile $libsFile
    7z x -y $libsFile -oC:\libs
}

# Install jom
$jomUrl = "https://download.qt.io/official_releases/jom/jom_1_1_3.zip"
$jomFile = "jom_1_1_3.zip"
if (-not (Test-Path $jomFile)) {
    Invoke-WebRequest -Uri $jomUrl -OutFile $jomFile
    7z x -y $jomFile -oc:\jom
}
# Add jom to PATH
echo "C:\jom" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append

# R Installation
if (-not (Test-Path 'C:\R')) {
    $rurl = "https://cran.r-project.org/bin/windows/base/old/4.1.3/R-4.1.3-win.exe"
    Invoke-WebRequest -Uri $rurl -OutFile "R-win.exe"
    Start-Process -FilePath .\R-win.exe -ArgumentList "/VERYSILENT /DIR=C:\R" -NoNewWindow -Wait
}
echo "C:\R\bin" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append

# Python Embedding
# We download the embeddable zip as in AppVeyor to be safe for the installer packaging
if (-not (Test-Path 'C:\Python3\python.exe')) {
    $pyurl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
    Invoke-WebRequest -Uri $pyurl -OutFile "python-embed.zip"
    Expand-Archive -Path python-embed.zip -DestinationPath C:\Python -Force
    
    # Enable pip in embedded Python
    $pthFile = "C:\Python\python311._pth"
    (Get-Content $pthFile) -replace '#import site', 'import site' | Set-Content $pthFile
    
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "get-pip.py"
    & C:\Python\python.exe get-pip.py --no-warn-script-location
}
echo "C:\Python" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
echo "C:\Python\Scripts" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append

# Install Python requirements into Embeddable Python (for packaging)
& C:\Python\python.exe -m pip install --upgrade pip
& C:\Python\python.exe -m pip install --only-binary :all: -r src/Python/requirements.txt

# Install Python requirements into System Python (for build/SIP)
# This is the python set up by setup-python action
python -m pip install --upgrade pip
python -m pip install --only-binary :all: -r src/Python/requirements.txt
