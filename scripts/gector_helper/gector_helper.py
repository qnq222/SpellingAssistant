#!/usr/bin/env python3
"""
Small local HTTP bridge between Spelling Popup Assistant and a GECToR checkout.

The app calls:
    POST /correct
    {"text": "..."}

The helper returns:
    {"originalText": "...", "correctedText": "...", "issues": [...]}
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import sys
import threading
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional


@dataclass(frozen=True)
class HelperConfig:
    host: str
    port: int
    backend: str
    gector_repo: Optional[Path]
    python: str
    model_paths: list[str]
    vocab_path: Optional[str]
    timeout: float
    min_error_probability: Optional[float]
    additional_confidence: Optional[float]
    special_tokens_fix: int


class CorrectionError(Exception):
    pass


class GECToRModelRunner:
    def __init__(self, config: HelperConfig) -> None:
        self.config = config
        self.model: Optional[Any] = None
        self.lock = threading.Lock()

    def correct(self, text: str) -> str:
        with self.lock:
            model = self.load_model()
            predictions, _ = model.handle_batch([text.split()])
            if not predictions:
                raise CorrectionError("GECToR returned no predictions.")
            return " ".join(predictions[0])

    def load_model(self) -> Any:
        if self.model is not None:
            return self.model

        config = self.config
        if config.gector_repo is None:
            raise CorrectionError("GECTOR_REPO is required for the predict backend.")
        if not config.model_paths:
            raise CorrectionError("At least one GECTOR_MODEL_PATH value is required.")
        if config.vocab_path is None:
            raise CorrectionError("GECTOR_VOCAB_PATH is required.")

        repo_path = str(config.gector_repo)
        if repo_path not in sys.path:
            sys.path.insert(0, repo_path)

        print("Loading GECToR model. The first load may download RoBERTa assets and take several minutes...", flush=True)
        from gector.gec_model import GecBERTModel

        self.model = GecBERTModel(
            vocab_path=config.vocab_path,
            model_paths=config.model_paths,
            min_error_probability=config.min_error_probability or 0.0,
            confidence=config.additional_confidence or 0.0,
            special_tokens_fix=config.special_tokens_fix,
            is_ensemble=0,
        )
        print("GECToR model loaded.", flush=True)
        return self.model


def correct_text(text: str, config: HelperConfig) -> dict[str, Any]:
    return correct_text_with_runner(text, config, None)


def correct_text_with_runner(text: str, config: HelperConfig, runner: Optional[GECToRModelRunner]) -> dict[str, Any]:
    normalized_text = text.strip()
    if not normalized_text:
        return {
            "originalText": text,
            "correctedText": text,
            "issues": [],
        }

    if config.backend == "echo":
        corrected_text = normalized_text
    elif config.backend == "predict":
        if runner is None:
            runner = GECToRModelRunner(config)
        corrected_text = runner.correct(normalized_text)
    else:
        raise CorrectionError(f"Unsupported backend: {config.backend}")

    return {
        "originalText": text,
        "correctedText": corrected_text,
        "issues": issue_summary(normalized_text, corrected_text),
    }


def issue_summary(original: str, corrected: str) -> list[dict[str, str]]:
    if original == corrected:
        return []

    original_tokens = original.split()
    corrected_tokens = corrected.split()
    matcher = difflib.SequenceMatcher(a=original_tokens, b=corrected_tokens)
    issues: list[dict[str, str]] = []

    for tag, original_start, original_end, corrected_start, corrected_end in matcher.get_opcodes():
        if tag == "equal":
            continue

        original_fragment = " ".join(original_tokens[original_start:original_end])
        replacement_fragment = " ".join(corrected_tokens[corrected_start:corrected_end])
        issues.append({
            "original": original_fragment,
            "replacement": replacement_fragment,
            "message": "GECToR grammar improvement",
        })

    if issues:
        return issues

    return [{
        "original": original,
        "replacement": corrected,
        "message": "GECToR grammar improvement",
    }]


def make_handler(config: HelperConfig) -> type[BaseHTTPRequestHandler]:
    runner = GECToRModelRunner(config) if config.backend == "predict" else None

    class GECToRRequestHandler(BaseHTTPRequestHandler):
        server_version = "GECToRHelper/1.0"

        def do_GET(self) -> None:
            if self.path == "/health":
                self.send_json(HTTPStatus.OK, {"ok": True, "backend": config.backend})
                return

            self.send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})

        def do_POST(self) -> None:
            if self.path != "/correct":
                self.send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
                return

            try:
                payload = self.read_json()
                text = payload.get("text")
                if not isinstance(text, str):
                    self.send_json(HTTPStatus.BAD_REQUEST, {"error": "Expected JSON body with a string 'text' field."})
                    return

                self.send_json(HTTPStatus.OK, correct_text_with_runner(text, config, runner))
            except CorrectionError as error:
                self.send_json(HTTPStatus.BAD_GATEWAY, {"error": str(error)})
            except json.JSONDecodeError:
                self.send_json(HTTPStatus.BAD_REQUEST, {"error": "Request body was not valid JSON."})
            except Exception as error:
                self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(error)})

        def read_json(self) -> dict[str, Any]:
            content_length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(content_length)
            parsed = json.loads(body.decode("utf-8"))
            if not isinstance(parsed, dict):
                raise json.JSONDecodeError("Expected JSON object", body.decode("utf-8"), 0)
            return parsed

        def send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args: Any) -> None:
            sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), format % args))

    return GECToRRequestHandler


def parse_args() -> HelperConfig:
    parser = argparse.ArgumentParser(description="Run a local GECToR HTTP helper.")
    parser.add_argument("--host", default=os.environ.get("GECTOR_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("GECTOR_PORT", "8765")))
    parser.add_argument("--backend", choices=["echo", "predict"], default=os.environ.get("GECTOR_BACKEND", "echo"))
    parser.add_argument("--gector-repo", default=os.environ.get("GECTOR_REPO"))
    parser.add_argument("--python", default=os.environ.get("GECTOR_PYTHON", sys.executable))
    parser.add_argument("--model-path", action="append", default=split_env_list(os.environ.get("GECTOR_MODEL_PATHS")))
    parser.add_argument("--vocab-path", default=os.environ.get("GECTOR_VOCAB_PATH"))
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("GECTOR_TIMEOUT", "20")))
    parser.add_argument("--min-error-probability", type=float, default=optional_float(os.environ.get("GECTOR_MIN_ERROR_PROBABILITY")))
    parser.add_argument("--additional-confidence", type=float, default=optional_float(os.environ.get("GECTOR_ADDITIONAL_CONFIDENCE")))
    parser.add_argument("--special-tokens-fix", action="store_true", default=os.environ.get("GECTOR_SPECIAL_TOKENS_FIX") == "1")

    args = parser.parse_args()
    return HelperConfig(
        host=args.host,
        port=args.port,
        backend=args.backend,
        gector_repo=Path(args.gector_repo).expanduser().resolve() if args.gector_repo else None,
        python=args.python,
        model_paths=args.model_path or [],
        vocab_path=args.vocab_path,
        timeout=args.timeout,
        min_error_probability=args.min_error_probability,
        additional_confidence=args.additional_confidence,
        special_tokens_fix=1 if args.special_tokens_fix else 0,
    )


def split_env_list(value: Optional[str]) -> list[str]:
    if not value:
        return []
    return [item for item in value.split(os.pathsep) if item]


def optional_float(value: Optional[str]) -> Optional[float]:
    if value in (None, ""):
        return None
    return float(value)


def main() -> None:
    config = parse_args()
    server = ThreadingHTTPServer((config.host, config.port), make_handler(config))
    print(f"GECToR helper listening on http://{config.host}:{config.port}/correct ({config.backend})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
