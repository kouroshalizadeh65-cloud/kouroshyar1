from __future__ import annotations

import base64
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

from .constants import EXPECTED_PUBLIC_KEY_B64, HOLIDAY_FEED_FORMAT, WORK_SCHEDULE_FEED_FORMAT


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any, compact: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, indent=None if compact else 2,
                      separators=(",", ":") if compact else None, sort_keys=False)
    path.write_text(text + ("" if compact else "\n"), encoding="utf-8")


def compact_json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def load_private_key(path: Path) -> Ed25519PrivateKey:
    raw = path.read_bytes()
    try:
        key = serialization.load_pem_private_key(raw, password=None)
    except (ValueError, TypeError):
        try:
            decoded = base64.b64decode(raw.strip(), validate=True)
        except Exception as exc:
            raise ValueError("کلید خصوصی نه PEM معتبر است و نه Base64 خام.") from exc
        if len(decoded) != 32:
            raise ValueError("کلید خصوصی خام Ed25519 باید دقیقاً ۳۲ بایت باشد.")
        key = Ed25519PrivateKey.from_private_bytes(decoded)
    if not isinstance(key, Ed25519PrivateKey):
        raise ValueError("کلید ارائه‌شده Ed25519 نیست.")
    return key


def raw_public_key_b64(private_key: Ed25519PrivateKey) -> str:
    public = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return base64.b64encode(public).decode("ascii")


def assert_expected_key(private_key: Ed25519PrivateKey, expected: str = EXPECTED_PUBLIC_KEY_B64) -> None:
    actual = raw_public_key_b64(private_key)
    if actual != expected:
        raise ValueError(f"کلید خصوصی با کلید عمومی نسخه نصب‌شده تطابق ندارد. actual={actual}")


def sign_payload(payload: dict[str, Any], private_key: Ed25519PrivateKey) -> dict[str, str]:
    payload_bytes = compact_json_bytes(payload)
    return {
        "format": payload["format"],
        "payload": base64.b64encode(payload_bytes).decode("ascii"),
        "signature": base64.b64encode(private_key.sign(payload_bytes)).decode("ascii"),
    }


def verify_envelope(envelope: dict[str, Any], public_key_b64: str = EXPECTED_PUBLIC_KEY_B64) -> dict[str, Any]:
    if not isinstance(envelope, dict):
        raise ValueError("ساختار envelope معتبر نیست.")
    payload = base64.b64decode(str(envelope["payload"]), validate=True)
    signature = base64.b64decode(str(envelope["signature"]), validate=True)
    public = base64.b64decode(public_key_b64, validate=True)
    Ed25519PublicKey.from_public_bytes(public).verify(signature, payload)
    decoded = json.loads(payload.decode("utf-8"))
    if envelope.get("format") != decoded.get("format"):
        raise ValueError("قالب envelope و payload یکسان نیست.")
    return decoded


def initial_payload(format_name: str) -> dict[str, Any]:
    key = "holidays" if format_name == HOLIDAY_FEED_FORMAT else "schedules"
    return {
        "format": format_name,
        "revision": 0,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        key: [],
    }


def load_existing_payload(envelope_path: Path, payload_path: Path, format_name: str) -> dict[str, Any]:
    if envelope_path.exists():
        payload = verify_envelope(read_json(envelope_path, {}))
        if payload.get("format") != format_name:
            raise ValueError(f"قالب فایل موجود اشتباه است: {payload.get('format')}")
        return payload
    payload = read_json(payload_path, initial_payload(format_name))
    if payload.get("format") != format_name:
        raise ValueError(f"قالب payload اشتباه است: {payload.get('format')}")
    return payload
