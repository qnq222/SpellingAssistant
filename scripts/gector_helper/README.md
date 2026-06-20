# GECToR Helper

This folder contains the optional local HTTP helper used by the app's `LanguageTool + GECToR` correction mode.

In that mode, the macOS app runs embedded LanguageTool first, applies local fallback spelling and high-confidence grammar rules, then sends sentence-like text to this helper for an additional local grammar pass.

## App Integration

The app expects:

```text
POST http://127.0.0.1:8765/correct
Content-Type: application/json

{ "text": "He go to school yesterday." }
```

The helper returns:

```json
{
  "originalText": "He go to school yesterday.",
  "correctedText": "He went to school yesterday.",
  "issues": [
    {
      "original": "go",
      "replacement": "went",
      "message": "GECToR grammar improvement"
    }
  ]
}
```

The app starts `run_roberta_helper.sh` in the background on launch and stops it on quit. Host and port are derived from the configured Settings endpoint. The default endpoint is:

```text
http://127.0.0.1:8765/correct
```

If the helper is missing, unavailable, slow, returns invalid JSON, or proposes a correction that removes negation markers, the app keeps the local LanguageTool result.

## Quick Smoke Test

Run the helper in echo mode:

```bash
python scripts/gector_helper/gector_helper.py
```

In another terminal:

```bash
curl -s http://127.0.0.1:8765/health
curl -s -X POST http://127.0.0.1:8765/correct \
  -H 'Content-Type: application/json' \
  -d '{"text":"He go to school yesterday."}'
```

Echo mode proves the app can talk to the helper, but it does not correct text.

## Install Official GECToR

The official GECToR project is at:

```text
https://github.com/grammarly/gector
```

It is a Python/PyTorch project based mainly on AllenNLP and Transformers. The upstream README says it was tested with Python 3.7.

Clone it and install dependencies with:

```bash
scripts/gector_helper/setup_gector.sh .gector
```

The setup script uses `python3` by default. For a Python 3.7 install, pass `PYTHON_BIN`:

```bash
PYTHON_BIN=/path/to/python3.7 scripts/gector_helper/setup_gector.sh .gector
```

The `.gector/` checkout and virtual environment are local development artifacts and are ignored by Git.

## Download A Pretrained Model

Download one of the pretrained model archives linked from the official README's `Pretrained models` section:

```text
https://github.com/grammarly/gector#pretrained-models
```

After extracting the archive, you need:

- the model file path, usually a `.th` file
- the vocabulary directory path

Model files such as `.th`, `.pt`, `.pth`, `.ckpt`, and `.safetensors` are ignored by Git because they are large generated/downloaded artifacts.

## Run With GECToR

For the RoBERTa model downloaded to `~/Downloads/roberta_1_gectorv2.th`, run:

```bash
scripts/gector_helper/run_roberta_helper.sh
```

This starts the helper in `predict` mode with the official RoBERTa confidence settings.

For a custom model path, use:

```bash
GECTOR_BACKEND=predict \
GECTOR_REPO="$PWD/.gector/gector" \
GECTOR_PYTHON="$PWD/.gector/venv/bin/python" \
GECTOR_MODEL_PATHS="/absolute/path/to/model.th" \
GECTOR_VOCAB_PATH="/absolute/path/to/vocabulary" \
python scripts/gector_helper/gector_helper.py
```

## Runtime Environment

`run_roberta_helper.sh` reads:

- `GECTOR_REPO`, defaulting to `.gector/gector`
- `GECTOR_PYTHON`, defaulting to `.gector/venv/bin/python`
- `GECTOR_MODEL_PATHS`, defaulting to `~/Downloads/roberta_1_gectorv2.th`
- `GECTOR_VOCAB_PATH`, defaulting to the upstream output vocabulary path
- `GECTOR_HOST`, defaulting to `127.0.0.1`
- `GECTOR_PORT`, defaulting to `8765`
- `GECTOR_ADDITIONAL_CONFIDENCE`, defaulting to `0.2`
- `GECTOR_MIN_ERROR_PROBABILITY`, defaulting to `0.5`
- `GECTOR_SPECIAL_TOKENS_FIX`, defaulting to `1`

## Notes

This helper wraps the official `predict.py` command:

```text
python predict.py --model_path MODEL_PATH --vocab_path VOCAB_PATH --input_file INPUT_FILE --output_file OUTPUT_FILE
```

That is the most stable integration point for the upstream project, but it may load the model per request. Once the model and quality are confirmed, a future optimization could keep the model warm in-process.
