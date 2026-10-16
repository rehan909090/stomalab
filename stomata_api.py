import logging
import math
import os
import sys
import threading
import traceback
from pathlib import Path

import cv2
import numpy as np
import requests
import yaml
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware


SAI_SOURCE = Path(os.environ.get("SAI_APP_SRC", "/opt/SAI-app/src"))
if not SAI_SOURCE.is_dir():
    raise RuntimeError(
        f"StomAI source not found at {SAI_SOURCE}. Run setup_stomai.sh in WSL first."
    )
sys.path.insert(0, str(SAI_SOURCE))

# StomAI memakai path relatif (./assets/config, ./assets/<species>, ./output/temp).
# Jadi kita jalankan dari folder data khusus dan buat semua subfolder yang dibutuhkan,
# supaya tidak error "No such file or directory: ./assets/config/....yaml".
DATA_DIR = Path(
    os.environ.get("STOMAI_DATA", Path(__file__).resolve().parent / "stomai_data")
)
for _sub in ("assets/config", "assets/arabidopsis", "assets/barley", "output/temp"):
    (DATA_DIR / _sub).mkdir(parents=True, exist_ok=True)
os.chdir(DATA_DIR)

# Unduhan bobot yang gagal/terpotong bisa menyisakan file rusak; hapus supaya diunduh ulang.
for _species in ("arabidopsis", "barley"):
    _weights = DATA_DIR / "assets" / _species / "weights.pth"
    if _weights.exists() and _weights.stat().st_size < 1_000_000:
        _weights.unlink()

# Wajib: mendaftarkan head kustom StomAI (KPROIHeads) ke registry detectron2.
from inference.modeling.stoma_head import KRCNNConvHead, KPROIHeads  # noqa: F401
from inference.infer import Inference_Engines, run_on_image
from tools.cloud_files import EXTERNAL_DEPENDANCIES
from tools.state import Option_State


MAX_UPLOAD_BYTES = 20 * 1024 * 1024
# Gambar besar (mis. 12 MP) membuat masker per-deteksi sangat besar di RAM -> proses di-kill OOM (exit 9).
# Gambar diperkecil untuk inferensi lalu koordinat dikembalikan ke ukuran asli.
MAX_INFER_SIDE = int(os.environ.get("STOMAI_MAX_SIDE", "4032"))
SUPPORTED_SPECIES = {"Arabidopsis", "Barley"}
INFERENCE_LOCK = threading.Lock()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("stomata_api")

app = FastAPI(title="StomAI local inference", docs_url=None, redoc_url=None)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://127.0.0.1:8000",
        "http://localhost:8000",
        "http://127.0.0.1:5500",
        "http://localhost:5500",
    ],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)


def _fetch(url):
    """Unduh dengan beberapa host cadangan figshare (host institusi 'adelaide' bisa memberi 403)."""
    file_id = url.rstrip("/").split("/")[-1]
    candidates = [
        url,
        f"https://ndownloader.figshare.com/files/{file_id}",
        f"https://figshare.com/ndownloader/files/{file_id}",
        f"https://api.figshare.com/v2/file/download/{file_id}",
    ]
    headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36"}
    errors = []
    for candidate in candidates:
        try:
            response = requests.get(candidate, timeout=180, allow_redirects=True, headers=headers)
            response.raise_for_status()
            if not response.content:
                raise RuntimeError("respons kosong")
            logger.info("GET %s -> HTTP %s, %d byte", candidate, response.status_code, len(response.content))
            return response.content
        except Exception as error:
            logger.warning("Gagal %s: %s", candidate, error)
            errors.append(f"{candidate} -> {error}")
    raise RuntimeError(
        "Semua sumber unduhan gagal (mungkin diblokir). Unduh manual lewat browser dan taruh di "
        f"folder stomai_data sesuai README. Detail: {' | '.join(errors)}"
    )


def _yaml_ok(path):
    try:
        with open(path, "r") as handle:
            data = yaml.safe_load(handle)
        return isinstance(data, dict) and len(data) > 0
    except Exception:
        return False


def ensure_model_files(species):
    """Pastikan config + bobot ada dan valid. File kosong/rusak dihapus lalu diunduh ulang.

    (Bug asli: config YAML kosong -> 'NoneType is not iterable' di detectron2 load_yaml_with_base.)
    """
    key = species.lower()
    config_dir = DATA_DIR / "assets" / "config"
    configs = [
        (config_dir / f"{key}.yaml", f"base_{key}_config"),
        (config_dir / f"{key}_v2.yaml", f"{key}_config"),
        (config_dir / "Base-RCNN-FPN.yaml", "base_config"),
    ]
    for path, dependency in configs:
        if path.exists() and not _yaml_ok(path):
            logger.warning("Config rusak/kosong, dihapus: %s", path)
            path.unlink()
        if not path.exists():
            url = EXTERNAL_DEPENDANCIES[dependency]
            logger.info("Mengunduh config %s", path.name)
            tmp = path.with_suffix(".tmp")
            tmp.write_bytes(_fetch(url))
            if not _yaml_ok(tmp):
                tmp.unlink()
                raise RuntimeError(
                    f"Unduhan config {path.name} kosong/tidak valid dari {url}. "
                    "Cek koneksi internet WSL, lalu coba lagi."
                )
            tmp.replace(path)

    weights = DATA_DIR / "assets" / key / "weights.pth"
    if weights.exists() and weights.stat().st_size < 1_000_000:
        weights.unlink()
    if not weights.exists():
        url = EXTERNAL_DEPENDANCIES[f"{key}_weights"]
        logger.info("Mengunduh bobot model %s (bisa lama)", key)
        content = _fetch(url)
        if len(content) < 1_000_000 or content[:1] == b"<":
            raise RuntimeError(
                f"Unduhan bobot {key} tidak valid ({len(content)} byte) dari {url}."
            )
        tmp = weights.with_suffix(".tmp")
        tmp.write_bytes(content)
        tmp.replace(weights)


def _where(error):
    """Lokasi (file:baris) terakhir dari traceback, supaya mudah dilacak."""
    frames = traceback.extract_tb(error.__traceback__)
    return " <- ".join(f"{Path(f.filename).name}:{f.lineno} {f.name}" for f in frames[-3:][::-1])


@app.get("/health")
def health():
    return {
        "status": "ready",
        "engine": "StomAI",
        "supported_species": sorted(SUPPORTED_SPECIES),
        "loaded_models": [
            species for species, engine in Inference_Engines.items() if engine is not None
        ],
    }


@app.post("/predict")
async def predict(image: UploadFile = File(...), species: str = Form(...)):
    if species not in SUPPORTED_SPECIES:
        raise HTTPException(
            status_code=422,
            detail=f"Spesies tidak didukung. Pilih salah satu: {', '.join(sorted(SUPPORTED_SPECIES))}.",
        )
    contents = await image.read(MAX_UPLOAD_BYTES + 1)
    await image.close()
    if not contents:
        raise HTTPException(status_code=400, detail="File gambar kosong.")
    if len(contents) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Ukuran gambar melebihi batas 20 MB.")
    frame = cv2.imdecode(np.frombuffer(contents, dtype=np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise HTTPException(status_code=400, detail="File tidak dapat dibaca sebagai gambar.")

    height, width = frame.shape[:2]
    scale = min(1.0, MAX_INFER_SIDE / max(height, width))
    infer_frame = frame
    if scale < 1.0:
        infer_frame = cv2.resize(
            frame, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_AREA
        )
    try:
        with INFERENCE_LOCK:
            ensure_model_files(species)
            Option_State["plant_type"] = species
            predictions, elapsed_seconds = run_on_image(infer_frame)
        detections = []
        for prediction in predictions.detections:
            category = prediction["category_id"]
            if category not in (0, 1):
                continue
            x1, y1, x2, y2 = prediction["bbox"]
            x1, y1, x2, y2 = (float(v) / scale for v in (x1, y1, x2, y2))
            confidence = float(prediction["confidence"])
            if not all(map(math.isfinite, (x1, y1, x2, y2, confidence))):
                continue
            detections.append(
                {
                    "x": min(max((x1 + x2) / 2, 0), width),
                    "y": min(max((y1 + y2) / 2, 0), height),
                    "box_width": max(x2 - x1, 0),
                    "box_height": max(y2 - y1, 0),
                    "status": "open" if category == 1 else "closed",
                    "confidence": confidence,
                }
            )
    except Exception as error:
        logger.exception("StomAI inference failed for %s image", species)
        raise HTTPException(
            status_code=500,
            detail=f"StomAI gagal memproses gambar: {error} | {_where(error)}",
        ) from error

    return {
        "engine": "StomAI",
        "species": species,
        "width": width,
        "height": height,
        "elapsed_seconds": round(float(elapsed_seconds), 3),
        "detections": detections,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8001)
