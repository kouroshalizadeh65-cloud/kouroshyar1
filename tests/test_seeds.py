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


def test_verified_notices_preserve_county_scope_and_remainder_rules():
    holidays, schedules, pending = load_verified_notices(ROOT)
    holiday_by_id = {item["id"]: item for item in holidays}
    schedule_by_id = {item["id"]: item for item in schedules}

    assert {
        "holiday-national-1405-04-14-mourning",
        "holiday-national-1405-04-15-funeral",
        "holiday-ilam-dehloran-1405-04-24",
    }.issubset(holiday_by_id)

    dehloran = holiday_by_id["holiday-ilam-dehloran-1405-04-24"]
    assert dehloran["scope"] == "county"
    assert dehloran["province"] == "ایلام"
    assert dehloran["counties"] == ["دهلران"]

    hot_counties = schedule_by_id["work-ilam-1405-04-23-hot-counties-close-11"]
    assert hot_counties["scope"] == "county"
    assert hot_counties["endTime"] == "11:00"
    assert hot_counties["counties"] == ["دهلران", "مهران", "آبدانان", "دره‌شهر", "سیروان"]

    other_counties = schedule_by_id["work-ilam-1405-04-23-other-counties-close-12"]
    assert other_counties["scope"] == "province"
    assert other_counties["endTime"] == "12:00"
    assert other_counties["excludedCounties"] == hot_counties["counties"]

    ilam_24 = schedule_by_id["work-ilam-1405-04-24-early-close-11"]
    assert ilam_24["scope"] == "province"
    assert ilam_24["excludedCounties"] == ["دهلران"]
    assert ilam_24["endTime"] == "11:00"

    assert schedule_by_id["work-khuzestan-1405-04-23-close-11"]["endTime"] == "11:00"
    assert schedule_by_id["work-khuzestan-1405-04-24-remote"]["scheduleType"] == "remote_work"

    ilam_28_two_hours = schedule_by_id["work-ilam-1405-04-28-dehloran-mehran-close-11"]
    assert ilam_28_two_hours["counties"] == ["دهلران", "مهران"]
    assert ilam_28_two_hours["endTime"] == "11:00"

    ilam_28_one_hour = schedule_by_id["work-ilam-1405-04-28-abdanan-darrehshahr-sirvan-close-12"]
    assert ilam_28_one_hour["counties"] == ["آبدانان", "دره‌شهر", "سیروان"]
    assert ilam_28_one_hour["endTime"] == "12:00"
    assert pending == []
