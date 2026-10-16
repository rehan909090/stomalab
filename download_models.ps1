# Unduh config + bobot model StomAI dari sisi Windows (jaringan Windows kadang lolos saat WSL diblokir 403).
# Pakai:  .\download_models.ps1            (Arabidopsis)
#         .\download_models.ps1 -Species Arabidopsis,Barley
param([string[]]$Species = @("Arabidopsis"))
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"
$root = Join-Path $PSScriptRoot "stomai_data\assets"

$files = @(
    @{ Id = 44321576; Path = "config\Base-RCNN-FPN.yaml"; Kind = "yaml"; For = "all" },
    @{ Id = 44321570; Path = "config\arabidopsis.yaml";    Kind = "yaml"; For = "arabidopsis" },
    @{ Id = 46517449; Path = "config\arabidopsis_v2.yaml"; Kind = "yaml"; For = "arabidopsis" },
    @{ Id = 46516891; Path = "arabidopsis\weights.pth";    Kind = "weights"; For = "arabidopsis" },
    @{ Id = 44321573; Path = "config\barley.yaml";         Kind = "yaml"; For = "barley" },
    @{ Id = 46517452; Path = "config\barley_v2.yaml";      Kind = "yaml"; For = "barley" },
    @{ Id = 46516888; Path = "barley\weights.pth";         Kind = "weights"; For = "barley" }
)
$wanted = @("all") + ($Species | ForEach-Object { $_.ToLower() })

function Test-Valid($path, $kind) {
    if (-not (Test-Path $path)) { return $false }
    $len = (Get-Item $path).Length
    if ($kind -eq "weights") { return $len -gt 1000000 }
    if ($len -lt 50) { return $false }
    $head = (Get-Content $path -TotalCount 1)
    return ($head -ne "null" -and $head -notmatch "^\s*<")
}

$failed = @()
foreach ($f in $files) {
    if ($wanted -notcontains $f.For) { continue }
    $dest = Join-Path $root $f.Path
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    if (Test-Valid $dest $f.Kind) { Write-Host "OK (sudah ada): $($f.Path)"; continue }
    if (Test-Path $dest) { Remove-Item $dest -Force }
    $done = $false
    foreach ($u in @("https://figshare.com/ndownloader/files/$($f.Id)",
                     "https://ndownloader.figshare.com/files/$($f.Id)",
                     "https://adelaide.figshare.com/ndownloader/files/$($f.Id)")) {
        try {
            Write-Host "Mengunduh $($f.Path) dari $u ..."
            Invoke-WebRequest -Uri $u -OutFile $dest -UserAgent $ua -UseBasicParsing -TimeoutSec 600
            if (Test-Valid $dest $f.Kind) { $done = $true; Write-Host "  berhasil."; break }
            Remove-Item $dest -Force -ErrorAction SilentlyContinue
        } catch { Write-Host "  gagal: $($_.Exception.Message)" }
    }
    if (-not $done) { $failed += $f }
}

if ($failed.Count -eq 0) { Write-Host "`nSemua file siap. Klik 'Deteksi stomata' di StomaLab."; return }

Write-Host "`nFile berikut tidak bisa diunduh lewat script (diblokir). Browser akan dibuka; simpan tiap file lalu pindahkan/rename:"
foreach ($f in $failed) {
    Write-Host ("  https://figshare.com/ndownloader/files/{0}  ->  stomai_data\assets\{1}" -f $f.Id, $f.Path)
    Start-Process "https://figshare.com/ndownloader/files/$($f.Id)"
}
Start-Process explorer.exe (Join-Path $PSScriptRoot "stomai_data\assets")
Write-Host "Setelah semua file ada, jalankan script ini lagi untuk memeriksa, lalu klik 'Deteksi stomata'."
