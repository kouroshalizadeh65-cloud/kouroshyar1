from pathlib import Path

from holiday_bot.seeds import load_official_holidays, load_official_work_schedules, load_verified_notices

ROOT = Path(__file__).resolve().parents[1]


def test_official_calendar_has_exact_26_holiday_dates():
    holidays, meta = load_official_holidays(ROOT)
    assert meta["sourceSha256"] == "8e32b520d5da058414b9378d62a01117273336a4c074591f4e84d59ab32a963c"
    assert len(holidays) == 26
    dates = {item["date"] for item in holidays}
    assert {"1405-01-01", "1405-03-14", "1405-06-08", "1405-12-29"}.issubset(dates)


def test_official_work_range_is_one_periodic_record():
    holidays, _ = load_official_holidays(ROOT)
    schedules = load_official_work_schedules(ROOT, {item["date"] for item in holidays})
    assert len(schedules) == 1
    schedule = schedules[0]
    assert schedule["id"] == "national-work-hours-1405-summer"
    assert schedule["date"] == "1405-02-26"
    assert schedule["endDate"] == "1405-06-15"
    assert schedule["scheduleType"] == "changed_hours"
    assert schedule["startTime"] == "07:00"
    assert schedule["endTime"] == "13:00"


def test_verified_ilam_notice_is_included_without_county_wide_false_positive():
    holidays, schedules, pending = load_verified_notices(ROOT)
    holiday_ids = {item["id"] for item in holidays}
    assert {"holiday-national-1405-04-14-mourning", "holiday-national-1405-04-15-funeral"}.issubset(holiday_ids)
    assert schedules[0]["id"] == "work-ilam-1405-04-24-early-close-11"
    assert schedules[0]["endTime"] == "11:00"
    assert any("شهرستانی" in item["reason"] for item in pending)
