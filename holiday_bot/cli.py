from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from .config import load_config
from .constants import BOT_VERSION, EXPECTED_PUBLIC_KEY_B64
from .engine import HealthGateError, run_update
from .storage import read_json, verify_envelope, write_json
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
    update.add_argument("--report-output", type=Path, default=_root() / "reports/workflow_result.json")

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
        sources = config["sources"]
        counts = {
            mode: sum(1 for source in sources if mode in source.get("modes", ["current"]))
            for mode in ("current", "backfill_1405")
        }
        by_kind: dict[str, int] = {}
        for source in sources:
            kind = str(source["kind"])
            by_kind[kind] = by_kind.get(kind, 0) + 1
        discovery_provinces = sorted({
            str(source.get("province"))
            for source in sources
            if source.get("coverage_role") == "province_discovery" and source.get("province")
        })
        official_channels = [
            source["name"]
            for source in sources
            if source.get("verified_official") and source.get("kind") == "public_channel"
        ]
        print(json.dumps({
            "ok": True,
            "botVersion": BOT_VERSION,
            "sources": len(sources),
            "sourcesByMode": counts,
            "sourcesByKind": by_kind,
            "provinceDiscoveryCoverage": len(discovery_provinces),
            "officialPublicChannels": official_channels,
            "currentLookbackHours": config.get("current_lookback_hours"),
            "contentRecheckHours": config.get("content_recheck_hours"),
            "healthGate": config.get("health_gate", {}),
            "fetchWorkers": config.get("fetch_workers", 8),
            "httpRetryAttempts": config.get("http_retry_attempts", 3),
            "httpRetryBackoffSeconds": config.get("http_retry_backoff_seconds", 2.0),
            "httpRetryMaxWaitSeconds": config.get("http_retry_max_wait_seconds", 30.0),
        }, ensure_ascii=False, indent=2))
    elif args.command == "verify":
        payload = verify_envelope(read_json(args.feed, {}), args.public_key)
        print(json.dumps({"ok": True, "format": payload.get("format"), "revision": payload.get("revision")}, ensure_ascii=False, indent=2))
    elif args.command == "validate":
        holidays = verify_envelope(read_json(args.holidays, {}), args.public_key)
        work = verify_envelope(read_json(args.working_hours, {}), args.public_key)
        stats = validate_payloads(holidays, work, require_baseline=True)
        print(json.dumps({"ok": True, **stats}, ensure_ascii=False, indent=2))
    else:
        exit_code = 0
        try:
            report = run_update(_root(), args.config, args.private_key, args.mode, args.dry_run)
        except HealthGateError as exc:
            report = exc.report
            report["error"] = str(exc)
            exit_code = 2
        except Exception as exc:
            report = {
                "botVersion": BOT_VERSION,
                "mode": args.mode,
                "dryRun": args.dry_run,
                "generatedAt": datetime.now(timezone.utc).isoformat(),
                "workflowStatus": "failed_no_publish",
                "publicationAllowed": False,
                "errorType": type(exc).__name__,
                "error": str(exc)[:1000],
            }
            exit_code = 1
        write_json(args.report_output, report)
        print(json.dumps(report, ensure_ascii=False, indent=2))
        if exit_code:
            raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
