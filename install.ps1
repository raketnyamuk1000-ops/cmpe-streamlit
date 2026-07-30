# CMPE Bootstrap Installer
$ErrorActionPreference = "Stop"

$repoOwner = "raketnyamuk1000-ops"   # <-- CHANGE THESE TWO LINES
$repoName  = "cmpe-streamlit"        # <-- BEFORE PUSHING TO GITHUB
$branch    = "main"

$zipUrl     = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip"
$tempZip    = "$env:TEMP\cmpe.zip"
$installDir = "$env:USERPROFILE\CMPE-Online"

Write-Host "Downloading CMPE from GitHub..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

Write-Host "Extracting..." -ForegroundColor Cyan
if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
Expand-Archive -Path $tempZip -DestinationPath $installDir -Force

$folder = Get-ChildItem -Path $installDir -Directory | Select-Object -First 1
Set-Location $folder.FullName

if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "`nPython not found." -ForegroundColor Red
    Write-Host "Install from https://www.python.org and check 'Add to PATH'`n"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Setting up environment..." -ForegroundColor Cyan
python -m venv venv
& .\venv\Scripts\Activate.ps1
pip install -q -r requirements.txt

Write-Host "`nGroq API key required." -ForegroundColor Yellow
$secureKey = Read-Host "Enter your Groq API key" -AsSecureString
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
$env:GROQ_API_KEY = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

Write-Host "`nLaunching CMPE..." -ForegroundColor Green
Start-Process "http://localhost:8501"
streamlit run app.py
