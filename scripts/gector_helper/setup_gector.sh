#!/bin/sh
set -eu

ROOT_DIR="${1:-$PWD/.gector}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
GECTOR_REPO="$ROOT_DIR/gector"
VENV_DIR="$ROOT_DIR/venv"

mkdir -p "$ROOT_DIR"

if [ ! -d "$GECTOR_REPO/.git" ]; then
  git clone https://github.com/grammarly/gector.git "$GECTOR_REPO"
else
  git -C "$GECTOR_REPO" pull --ff-only
fi

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install -r "$GECTOR_REPO/requirements.txt"

cat <<EOF

GECToR repo: $GECTOR_REPO
Python env:  $VENV_DIR

Download one of the pretrained model archives from:
https://github.com/grammarly/gector#pretrained-models

Then run:

GECTOR_BACKEND=predict \\
GECTOR_REPO="$GECTOR_REPO" \\
GECTOR_PYTHON="$VENV_DIR/bin/python" \\
GECTOR_MODEL_PATHS="/path/to/model.th" \\
GECTOR_VOCAB_PATH="/path/to/vocabulary" \\
python scripts/gector_helper/gector_helper.py

EOF
