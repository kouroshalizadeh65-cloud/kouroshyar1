from __future__ import annotations

import argparse
import json
from pathlib import Path

from .config import load_config
from .constants import BOT_VERSION, EXPECTED_PUBLIC_KEY_B64
from .engine import run_update
from .storage import read_json, verify_envelope
from .validate import validate_payloads


def _root() -> Path:
    return Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=f"ربات تعطیلات رسمی کوروش‌یار v{BOT_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    update = sub.add_parser("update", help="دریافت، طبقه‌بندی، اعتبارسنجی و انتشار داده")
    update.add_argument("--mode", choices=("current", "backfill_1405"), default="current")
    update.add_argument("--config", type=Path, default=_root() / "config/sources.yaml")
    update.add_argument("--private-key", type=Path, required=True)
    update.add_argument("--dry-run", action="store_true")

    doctor = sub.add_parser("doctor", help="کنترل ساختار تنظیمات")
    doctor.add_argument("--config", type=Path, default=_root() / "config/sources.yaml")

    verify = sub.add_parser("verify", help="کنترل امضای فایل خروجی")
    verify.add_argument("--feed", type=Path, required=True)
    verify.add_argument("--public-key", default=EXPECTED_PUBLIC_KEY_B64)

    validate = sub.add_parser("validate", help="کنترل محتوای هر دو خوراک")
    validate.add_argument("--holidays", type=Path, default=_root() / "holiday_feed/holidays.json")
    validate.add_argument("--working-hours", type=Path, default=_root() / "holiday_feed/working_hours.json")
    validate.add_argument("--public-key", default=EXPECTED_PUBLIC_KEY_B64)

    args = parser.parse_args()
    if args.command == "doctor":
        config = load_config(args.config)
        counts = {mode: sum(1 for s in config["sources"] if mode in s.get("modes", ["current"])) for mode in ("current", "backfill_1405")}
        print(json.dumps({"ok": True, "botVersion": BOT_VERSION, "sources": len(config["sources"]), "sourcesByMode": counts}, ensure_ascii=False, indent=2))
    elif args.command == "verify":
        payload = verify_envelope(read_json(args.feed, {}), args.public_key)
        print(json.dumps({"ok": True, "format": payload.get("format"), "revision": payload.get("revision")}, ensure_ascii=False, indent=2))
    elif args.command == "validate":
        holidays = verify_envelope(read_json(args.holidays, {}), args.public_key)
        work = verify_envelope(read_json(args.working_hours, {}), args.public_key)
        stats = validate_payloads(holidays, work, require_baseline=True)
        print(json.dumps({"ok": True, **stats}, ensure_ascii=False, indent=2))
    else:
        report = run_update(_root(), args.config, args.private_key, args.mode, args.dry_run)
        print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
