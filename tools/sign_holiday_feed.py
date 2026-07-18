#!/usr/bin/env python3
"""Sign a KouroshYar holiday payload with an Ed25519 private key.

The private key is read from a file outside the source tree. The output is the
small JSON envelope consumed by the Android application.
"""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

FORMAT = "kouroshyar-holiday-feed-v1"


def compact_json_bytes(path: Path) -> bytes:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != FORMAT:
        raise SystemExit(f"payload format must be {FORMAT}")
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def load_private_key(path: Path) -> Ed25519PrivateKey:
    raw = path.read_bytes()
    try:
        key = serialization.load_pem_private_key(raw, password=None)
    except ValueError:
        decoded = base64.b64decode(raw.strip(), validate=True)
        if len(decoded) != 32:
            raise SystemExit("raw Ed25519 private key must be exactly 32 bytes")
        key = Ed25519PrivateKey.from_private_bytes(decoded)
    if not isinstance(key, Ed25519PrivateKey):
        raise SystemExit("the supplied key is not an Ed25519 private key")
    return key


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path)
    parser.add_argument("private_key", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--public-key-output", type=Path)
    args = parser.parse_args()

    payload_bytes = compact_json_bytes(args.payload)
    private_key = load_private_key(args.private_key)
    signature = private_key.sign(payload_bytes)
    envelope = {
        "format": FORMAT,
        "payload": base64.b64encode(payload_bytes).decode("ascii"),
        "signature": base64.b64encode(signature).decode("ascii"),
    }
    args.output.write_text(
        json.dumps(envelope, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if args.public_key_output:
        public_bytes = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        args.public_key_output.write_text(
            base64.b64encode(public_bytes).decode("ascii") + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
