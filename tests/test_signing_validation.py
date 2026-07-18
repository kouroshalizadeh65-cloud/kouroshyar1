import base64
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from holiday_bot.constants import HOLIDAY_FEED_FORMAT, WORK_SCHEDULE_FEED_FORMAT
from holiday_bot.seeds import load_official_holidays, load_official_work_schedules, load_verified_notices
from holiday_bot.storage import sign_payload, verify_envelope
from holiday_bot.validate import validate_payloads

ROOT = Path(__file__).resolve().parents[1]


def test_seed_payloads_validate_and_sign():
    holidays, _ = load_official_holidays(ROOT)
    schedules = load_official_work_schedules(ROOT, {x["date"] for x in holidays})
    verified_holidays, verified_schedules, _ = load_verified_notices(ROOT)
    hp = {"format": HOLIDAY_FEED_FORMAT, "revision": 1, "generatedAt": "2026-07-18T00:00:00Z", "holidays": holidays + verified_holidays}
    wp = {"format": WORK_SCHEDULE_FEED_FORMAT, "revision": 1, "generatedAt": "2026-07-18T00:00:00Z", "schedules": schedules + verified_schedules}
    stats = validate_payloads(hp, wp, True)
    assert stats["officialHolidayDates"] == 26
    key = Ed25519PrivateKey.generate()
    public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    public_b64 = base64.b64encode(public).decode("ascii")
    assert verify_envelope(sign_payload(hp, key), public_b64) == hp
    assert verify_envelope(sign_payload(wp, key), public_b64) == wp
