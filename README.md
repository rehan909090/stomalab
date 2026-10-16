# StomaLab + StomAI

Web lokal untuk meninjau deteksi stomata. Deteksi otomatis memakai model StomAI (Arabidopsis / Barley). Gambar diproses di komputer sendiri.

## Cara pakai (Windows + VS Code)

Prasyarat: WSL dengan Ubuntu 22.04 (`wsl --install -d Ubuntu-22.04`), dan Python di Windows (untuk web server statis).

1. Extract zip, buka foldernya di VS Code (File > Open Folder).
2. **Sekali saja:** `Ctrl+Shift+P` > *Tasks: Run Task* > **StomaLab: Setup (sekali saja)**
   (atau di terminal: `.\setup_stomai.ps1`). Butuh internet, 10-30 menit.
3. **Tiap kali mau pakai:** *Tasks: Run Task* > **StomaLab: Run** (atau `.\run_stomai.ps1`). Biarkan terminalnya terbuka.
4. Buka http://127.0.0.1:8000 (jangan klik dua kali index.html).
5. Upload gambar, pilih spesies, klik **Deteksi stomata**. Deteksi pertama tiap spesies mengunduh bobot model, jadi lama.
6. Berhenti: Ctrl+C, atau task **StomaLab: Stop**.

Kalau PowerShell menolak menjalankan script: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## Troubleshooting

- `address already in use` (port 8001): jalankan `.\stop_stomai.ps1`, lalu `.\run_stomai.ps1`.
- `No such file ... assets/config/...yaml`: sudah diperbaiki; API membuat folder `stomai_data/` sendiri.
- Bobot model gagal diunduh / file rusak: hapus `stomai_data/assets/<spesies>/weights.pth` lalu deteksi ulang.
- Cek API hidup: http://127.0.0.1:8001/health

## Nilai analisis

- Jumlah open/closed dari kelas prediksi model.
- Kepadatan abaxial = (open + closed) / luas bidang (mm2), dari lebar bidang yang kamu isi. Hanya untuk permukaan abaxial.
- Persen open = open / (open + closed) x 100. Edit manual langsung memperbarui nilai.
- Export PNG berisi gambar asli dengan lingkaran bernomor.

## Cakupan model dan sitasi

Hanya model Arabidopsis dan Barley. Gambar dari spesies/mikroskop/perbesaran lain bisa di luar distribusi; selalu periksa hasilnya. Upstream [SAI-app](https://github.com/XDynames/SAI-app) berlisensi GPL-3.0. Sitasi:

> Sai, N. et al. (2023). StomaAI: an efficient and user-friendly tool for measurement of stomatal pores and density using deep computer vision. *New Phytologist*, 238(2), 904-915. https://doi.org/10.1111/nph.18765
