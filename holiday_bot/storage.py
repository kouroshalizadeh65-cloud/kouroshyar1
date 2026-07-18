from __future__ import annotations

import base64
import json
import subprocess
from dataclasses import dataclass
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


def _payload_revision(payload: dict[str, Any], format_name: str) -> int:
    if payload.get("format") != format_name:
        raise ValueError(f"قالب payload اشتباه است: {payload.get('format')}")
    revision = payload.get("revision")
    if not isinstance(revision, int) or revision < 0:
        raise ValueError("شماره بازبینی payload معتبر نیست.")
    return revision


def _git_file_versions(root: Path, relative_path: str, limit: int = 80) -> list[tuple[str, bytes]]:
    if not (root / ".git").exists():
        return []
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "log", "--format=%H", "--all", "--", relative_path],
            check=True, capture_output=True, text=True, timeout=20,
        )
    except Exception:
        return []
    versions: list[tuple[str, bytes]] = []
    for commit in [line.strip() for line in result.stdout.splitlines() if line.strip()][:limit]:
        try:
            shown = subprocess.run(
                ["git", "-C", str(root), "show", f"{commit}:{relative_path}"],
                check=True, capture_output=True, timeout=10,
            )
        except Exception:
            continue
        versions.append((commit, shown.stdout))
    return versions


@dataclass(frozen=True)
class PayloadLoadState:
    payload: dict[str, Any]
    highest_revision: int
    source: str
    current_envelope_revision: int | None
    current_payload_revision: int | None
    restore_required: bool
    historical_candidates: int


def load_existing_payload_state(
    root: Path,
    envelope_path: Path,
    payload_path: Path,
    format_name: str,
) -> PayloadLoadState:
    candidates: list[tuple[int, int, str, dict[str, Any]]] = []
    current_envelope_revision: int | None = None
    current_payload_revision: int | None = None

    if envelope_path.exists():
        payload = verify_envelope(read_json(envelope_path, {}))
        revision = _payload_revision(payload, format_name)
        current_envelope_revision = revision
        candidates.append((revision, 4, "current-envelope", payload))
    if payload_path.exists():
        payload = read_json(payload_path, {})
        revision = _payload_revision(payload, format_name)
        current_payload_revision = revision
        candidates.append((revision, 3, "current-payload", payload))

    history_count = 0
    for path, signed, priority in ((envelope_path, True, 2), (payload_path, False, 1)):
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            continue
        for commit, raw in _git_file_versions(root, relative):
            history_count += 1
            try:
                decoded = json.loads(raw.decode("utf-8"))
                payload = verify_envelope(decoded) if signed else decoded
                revision = _payload_revision(payload, format_name)
            except Exception:
                continue
            candidates.append((revision, priority, f"git:{commit[:12]}:{relative}", payload))

    if not candidates:
        payload = initial_payload(format_name)
        return PayloadLoadState(payload, 0, "initial", None, None, True, history_count)

    # بالاترین revision منبع حقیقت است؛ در تساوی، فایل امضاشده فعلی اولویت دارد.
    revision, _priority, source, payload = max(candidates, key=lambda item: (item[0], item[1]))
    restore_required = (
        current_envelope_revision != revision
        or current_payload_revision != revision
        or not envelope_path.exists()
        or not payload_path.exists()
    )
    return PayloadLoadState(
        payload=dict(payload),
        highest_revision=revision,
        source=source,
        current_envelope_revision=current_envelope_revision,
        current_payload_revision=current_payload_revision,
        restore_required=restore_required,
        historical_candidates=history_count,
    )


def load_existing_payload(envelope_path: Path, payload_path: Path, format_name: str) -> dict[str, Any]:
    """سازگاری با فراخوان‌های قدیمی؛ بدون بازیابی تاریخچه Git."""
    common = envelope_path.parent.parent
    return load_existing_payload_state(common, envelope_path, payload_path, format_name).payload
