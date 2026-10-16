# Menghentikan server API (WSL) dan web server (port 8000).
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\_common.ps1"

try {
    $distro = Resolve-Distro
    & wsl.exe -d $distro --exec bash -lc "pkill -f '^/opt/stomai-venv/bin/python.* stomata_api:app' && echo 'API dihentikan.' || echo 'API tidak sedang berjalan.'"
} catch { Write-Warning $_ }

Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
    Write-Host "Web server port 8000 dihentikan (PID $($_.OwningProcess))."
}
