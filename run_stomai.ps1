$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_common.ps1"

$siteUrl = "http://127.0.0.1:8000/"
$apiUrl  = "http://127.0.0.1:8001/health"

# 1) Web server statis untuk index.html (port 8000)
$siteUp = $false
try { $null = Invoke-WebRequest -Uri $siteUrl -UseBasicParsing -TimeoutSec 2; $siteUp = $true } catch {}
if (-not $siteUp) {
    $py = $null
    if (Get-Command python -ErrorAction SilentlyContinue) { $py = @{ File = "python"; Args = @("-m", "http.server", "8000", "--bind", "127.0.0.1") } }
    elseif (Get-Command py -ErrorAction SilentlyContinue) { $py = @{ File = "py"; Args = @("-3", "-m", "http.server", "8000", "--bind", "127.0.0.1") } }
    if ($py) {
        $null = Start-Process -FilePath $py.File -ArgumentList $py.Args -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    } else {
        Write-Warning "Python Windows tidak ditemukan. Install Python, atau buka index.html dengan VS Code Live Server (port 5500)."
    }
}

# 2) Kalau API sudah hidup, tidak perlu start lagi
try {
    $r = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 2
    if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
        Write-Host "StomaLab: $siteUrl"
        Write-Host "StomAI API sudah berjalan. Tidak start duplikat."
        return
    }
} catch {}

# 3) Start API di WSL
$distro = Resolve-Distro -NeedVenv
$lp = Get-LinuxPath $distro $PSScriptRoot

Write-Host "StomaLab:        $siteUrl"
Write-Host "StomAI local API: http://127.0.0.1:8001  (distro: $distro)"
Write-Host "Biarkan window ini terbuka selama dipakai. Ctrl+C untuk berhenti."
Write-Host "Deteksi pertama tiap spesies mengunduh bobot model (butuh internet), jadi agak lama."

# pkill memakai pola berjangkar (^) agar hanya cocok dengan proses python uvicorn, bukan shell ini sendiri; membersihkan sisa server lama di port 8001.
$cmd = "pkill -f '^/opt/stomai-venv/bin/python.* stomata_api:app' 2>/dev/null; sleep 1; cd '$lp' && exec /opt/stomai-venv/bin/uvicorn stomata_api:app --app-dir '$lp' --host 0.0.0.0 --port 8001"
& wsl.exe -d $distro --exec bash -lc $cmd
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 130) {
    throw "Server StomAI berhenti dengan exit code $LASTEXITCODE. Jika 'address already in use', jalankan .\stop_stomai.ps1 lalu coba lagi."
}
