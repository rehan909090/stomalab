# Helper bersama untuk setup/run/stop. File ini ASCII-only supaya aman di Windows PowerShell 5.1.
$script:PreferredDistro = "StomaLabUbuntu"

function Get-WslDistros {
    $raw = & wsl.exe -l -q 2>$null | Out-String
    return ($raw -replace "`0", "") -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Resolve-Distro([switch]$NeedVenv) {
    $distros = @(Get-WslDistros)
    if ($distros.Count -eq 0) {
        throw "WSL belum terpasang / belum ada distro. Jalankan 'wsl --install -d Ubuntu-22.04' di PowerShell (Admin), restart, lalu coba lagi."
    }
    $candidates = @()
    if ($distros -contains $script:PreferredDistro) { $candidates += $script:PreferredDistro }
    $candidates += ($distros | Where-Object { $_ -like "Ubuntu*" -and $_ -ne $script:PreferredDistro })
    if ($NeedVenv) {
        foreach ($d in $candidates) {
            & wsl.exe -d $d --exec test -x /opt/stomai-venv/bin/uvicorn 2>$null
            if ($LASTEXITCODE -eq 0) { return $d }
        }
        throw "StomAI belum ter-install di WSL. Jalankan dulu: .\setup_stomai.ps1"
    }
    if ($candidates.Count -eq 0) {
        throw "Tidak ada distro Ubuntu di WSL. Jalankan: wsl --install -d Ubuntu-22.04"
    }
    return $candidates[0]
}

function Get-LinuxPath([string]$distro, [string]$winPath) {
    $p = (& wsl.exe -d $distro --exec wslpath -a $winPath | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $p) { throw "Gagal mengonversi path ke WSL: $winPath" }
    return $p
}
