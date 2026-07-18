from datetime import datetime, timezone

from holiday_bot.dates import extract_jalali_dates, extract_jalali_range, extract_times, is_friday
from holiday_bot.extract import parse_published


def test_extract_range_and_times_from_official_notice():
    text = "ساعت کاری جدید ادارات از شنبه 26 اردیبهشت 1405 تا روز 15 شهریور 1405 از ساعت 7 تا 13 خواهد بود."
    published = datetime(2026, 5, 15, tzinfo=timezone.utc)
    assert extract_jalali_range(text, published, 1405) == ("1405-02-26", "1405-06-15")
    assert extract_times(text) == ("07:00", "13:00")


def test_extract_persian_digits_and_relative_date():
    published = datetime(2026, 7, 14, tzinfo=timezone.utc)
    assert "1405-04-24" in extract_jalali_dates("فردا چهارشنبه ۲۴ تیرماه ۱۴۰۵", published, 1405)


def test_extract_end_time_for_early_close():
    assert extract_times("فعالیت ادارات با دو ساعت تعجیل در پایان وقت اداری (ساعت ۱۱) به پایان می‌رسد") == (None, "11:00")


def test_friday_detection():
    assert is_friday("1405-03-15") is True
    assert is_friday("1405-02-26") is False


def test_parse_published_persian_text_date():
    parsed = parse_published("سه‌شنبه 23 تیر 1405 - 21:28")
    assert parsed.isoformat() == "2026-07-14T17:58:00+00:00"
