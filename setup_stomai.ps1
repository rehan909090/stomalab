# Satu kali saja: install StomAI + dependensi di WSL Ubuntu (butuh internet, bisa 10-30 menit).
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_common.ps1"

$distro = Resolve-Distro
Write-Host "Memakai distro WSL: $distro"
$lp = Get-LinuxPath $distro $PSScriptRoot

# Cek Python 3.10
& wsl.exe -d $distro --exec bash -lc "command -v python3.10 >/dev/null"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Python 3.10 belum ada, memasang (butuh root)..."
    & wsl.exe -d $distro -u root --exec bash -lc "apt-get update && apt-get install -y python3.10 python3.10-venv python3-pip git libgl1 libglib2.0-0 build-essential"
    if ($LASTEXITCODE -ne 0) { throw "Gagal memasang Python 3.10. Pakai Ubuntu 22.04 (wsl --install -d Ubuntu-22.04)." }
}

# Dijalankan sebagai root karena target install ada di /opt
& wsl.exe -d $distro -u root --exec bash -lc "apt-get install -y git libgl1 libglib2.0-0 build-essential >/dev/null 2>&1; cd '$lp' && sed -i 's/\r$//' setup_stomai.sh && bash setup_stomai.sh"
if ($LASTEXITCODE -ne 0) { throw "Setup gagal (exit $LASTEXITCODE). Lihat pesan error di atas." }
Write-Host ""
Write-Host "Setup selesai. Sekarang jalankan: .\run_stomai.ps1"
