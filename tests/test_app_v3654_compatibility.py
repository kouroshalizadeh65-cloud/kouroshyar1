from datetime import datetime
from pathlib import Path

from holiday_bot.constants import HOLIDAY_FEED_FORMAT, WORK_SCHEDULE_FEED_FORMAT
from holiday_bot.seeds import load_official_holidays, load_official_work_schedules, load_verified_notices
from holiday_bot.storage import compact_json_bytes
from holiday_bot.validate import validate_payloads

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_HOLIDAY_TYPES = {"official", "national_emergency", "provincial", "administrative", "judiciary"}
ALLOWED_SCHEDULE_TYPES = {"changed_hours", "remote_work", "delayed_start", "early_close"}
ALLOWED_SCOPES = {"national", "province", "county", "organization"}
ALLOWED_STATUSES = {"active", "updated", "cancelled"}


def _parse_iso(value: str) -> None:
    datetime.fromisoformat(value.replace("Z", "+00:00"))


def test_seed_payload_matches_app_v3659_schema_and_limits():
    holidays, _ = load_official_holidays(ROOT)
    schedules = load_official_work_schedules(ROOT, {item["date"] for item in holidays})
    verified_holidays, verified_schedules, _ = load_verified_notices(ROOT)
    holidays += verified_holidays
    schedules += verified_schedules
    hp = {"format": HOLIDAY_FEED_FORMAT, "revision": 2, "generatedAt": "2026-07-18T00:00:00+00:00", "holidays": holidays}
    wp = {"format": WORK_SCHEDULE_FEED_FORMAT, "revision": 2, "generatedAt": "2026-07-18T00:00:00+00:00", "schedules": schedules}
    validate_payloads(hp, wp, True)
    assert len(holidays) <= 1000
    assert len(schedules) <= 1500
    assert len(compact_json_bytes(hp)) < 1024 * 1024
    assert len(compact_json_bytes(wp)) < 1024 * 1024
    for item in holidays:
        assert item["type"] in ALLOWED_HOLIDAY_TYPES
        assert item["scope"] in ALLOWED_SCOPES
        assert item["status"] in ALLOWED_STATUSES
        assert len(item["id"]) <= 120
        _parse_iso(item["publishedAt"])
        assert str(item["sourceUrl"]).startswith("https://")
        if item["scope"] == "county":
            assert item.get("province")
            assert item.get("counties")
        if item.get("excludedCounties"):
            assert item.get("province")
    for item in schedules:
        assert item["scheduleType"] in ALLOWED_SCHEDULE_TYPES
        assert item["scope"] in ALLOWED_SCOPES
        assert item["status"] in ALLOWED_STATUSES
        assert len(item["id"]) <= 120
        _parse_iso(item["publishedAt"])
        assert str(item["sourceUrl"]).startswith("https://")
        if item["scope"] == "county":
            assert item.get("province")
            assert item.get("counties")
        if item.get("excludedCounties"):
            assert item.get("province")
        for key in ("startTime", "endTime"):
            if key in item:
                assert len(item[key]) == 5 and item[key][2] == ":"
