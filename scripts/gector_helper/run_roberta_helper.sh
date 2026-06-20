#!/bin/sh
set -eu

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GECTOR_REPO="${GECTOR_REPO:-$PROJECT_ROOT/.gector/gector}"
GECTOR_PYTHON="${GECTOR_PYTHON:-$PROJECT_ROOT/.gector/venv/bin/python}"
GECTOR_MODEL_PATHS="${GECTOR_MODEL_PATHS:-$HOME/Downloads/roberta_1_gectorv2.th}"
GECTOR_VOCAB_PATH="${GECTOR_VOCAB_PATH:-$GECTOR_REPO/data/output_vocabulary}"
GECTOR_HOST="${GECTOR_HOST:-127.0.0.1}"
GECTOR_PORT="${GECTOR_PORT:-8765}"

if [ ! -x "$GECTOR_PYTHON" ]; then
  echo "Missing GECToR Python environment: $GECTOR_PYTHON" >&2
  echo "Run: scripts/gector_helper/setup_gector.sh .gector" >&2
  exit 1
fi

if [ ! -f "$GECTOR_REPO/predict.py" ]; then
  echo "Missing GECToR predict.py: $GECTOR_REPO/predict.py" >&2
  exit 1
fi

if [ ! -f "$GECTOR_MODEL_PATHS" ]; then
  echo "Missing RoBERTa model: $GECTOR_MODEL_PATHS" >&2
  exit 1
fi

if [ ! -d "$GECTOR_VOCAB_PATH" ]; then
  echo "Missing GECToR vocabulary directory: $GECTOR_VOCAB_PATH" >&2
  exit 1
fi

export GECTOR_BACKEND=predict
export GECTOR_REPO
export GECTOR_PYTHON
export GECTOR_MODEL_PATHS
export GECTOR_VOCAB_PATH
export GECTOR_ADDITIONAL_CONFIDENCE="${GECTOR_ADDITIONAL_CONFIDENCE:-0.2}"
export GECTOR_MIN_ERROR_PROBABILITY="${GECTOR_MIN_ERROR_PROBABILITY:-0.5}"
export GECTOR_SPECIAL_TOKENS_FIX="${GECTOR_SPECIAL_TOKENS_FIX:-1}"

exec "$GECTOR_PYTHON" "$PROJECT_ROOT/scripts/gector_helper/gector_helper.py" --host "$GECTOR_HOST" --port "$GECTOR_PORT" --backend predict
