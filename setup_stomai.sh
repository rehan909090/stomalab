#!/usr/bin/env bash
set -euo pipefail

SAI_DIR="${SAI_APP_DIR:-/opt/SAI-app}"
VENV_DIR="${STOMAI_VENV:-/opt/stomai-venv}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3.10 >/dev/null 2>&1; then
    echo "Python 3.10 is required. This setup is intended for Ubuntu 22.04 on WSL." >&2
    exit 1
fi

if [[ ! -d "$SAI_DIR/.git" ]]; then
    git clone --depth 1 https://github.com/XDynames/SAI-app.git "$SAI_DIR"
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3.10 -m venv "$VENV_DIR"
fi

PYTHON="$VENV_DIR/bin/python"
"$PYTHON" -m pip install --upgrade pip 'setuptools==75.3.3' 'wheel==0.45.1' 'packaging<24'
"$PYTHON" - <<'PY'
import pkg_resources, setuptools
print(f"setuptools={setuptools.__version__}")
print(f"pkg_resources={pkg_resources.__file__}")
PY
"$PYTHON" -m pip install \
    --find-links https://download.pytorch.org/whl/torch_stable.html \
    torch==1.11.0+cpu torchvision==0.12.0+cpu torchaudio==0.11.0+cpu
"$PYTHON" -m pip install -c "$PROJECT_DIR/stomai-constraints.txt" -r "$SAI_DIR/requirements.txt"
"$PYTHON" -m pip install --no-build-isolation --no-deps \
    git+https://github.com/facebookresearch/detectron2.git@v0.6
"$PYTHON" -m pip install --no-deps -e "$SAI_DIR"
"$PYTHON" -m pip install -c "$PROJECT_DIR/stomai-constraints.txt" \
    fastapi==0.103.2 uvicorn==0.23.2 python-multipart==0.0.9

echo "StomAI dependencies are installed. Start the local server with run_stomai.ps1."
