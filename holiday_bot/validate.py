from __future__ import annotations

import re
from typing import Any

from .constants import HOLIDAY_FEED_FORMAT, WORK_SCHEDULE_FEED_FORMAT
from .dates import parse_jalali

_HTTPS = re.compile(r"^https://[^\s]+$")
_TIME = re.compile(r"^(?:[01]\d|2[0-3]):[0-5]\d$")


def _text(item: dict[str, Any], key: str, max_len: int = 1000) -> str:
    value = str(item.get(key, "")).strip()
    if not value or len(value) > max_len:
        raise ValueError(f"فیلد {key} نامعتبر است.")
    return value


def _string_list(item: dict[str, Any], key: str, max_items: int = 100) -> list[str]:
    value = item.get(key, [])
    if value is None:
        return []
    if not isinstance(value, list) or len(value) > max_items:
        raise ValueError(f"فیلد {key} باید فهرست معتبر باشد.")
    result: list[str] = []
    for raw in value:
        text = str(raw).strip()
        if not text or len(text) > 120:
            raise ValueError(f"یکی از مقادیر {key} نامعتبر است.")
        if text not in result:
            result.append(text)
    return result


def validate_holiday_item(item: dict[str, Any]) -> None:
    _text(item, "id", 120)
    parse_jalali(_text(item, "date", 10))
    _text(item, "title")
    if _text(item, "type", 40) not in {"official", "national_emergency", "provincial", "administrative", "judiciary"}:
        raise ValueError("نوع تعطیلی نامعتبر است.")
    scope = _text(item, "scope", 40)
    if scope not in {"national", "province", "county", "organization"}:
        raise ValueError("دامنه تعطیلی نامعتبر است.")
    if scope in {"province", "county"} and not str(item.get("province", "")).strip():
        raise ValueError("استان تعطیلی خالی است.")
    counties = _string_list(item, "counties")
    _string_list(item, "excludedCounties")
    if scope == "county" and not counties:
        raise ValueError("برای تعطیلی شهرستانی باید نام شهرستان درج شود.")
    _text(item, "authority")
    if item.get("sourceUrl") and not _HTTPS.match(str(item["sourceUrl"])):
        raise ValueError("نشانی منبع تعطیلی HTTPS نیست.")
    if _text(item, "status", 40) not in {"active", "updated", "cancelled"}:
        raise ValueError("وضعیت تعطیلی نامعتبر است.")


def validate_schedule_item(item: dict[str, Any]) -> None:
    _text(item, "id", 120)
    start = _text(item, "date", 10)
    parse_jalali(start)
    if item.get("endDate"):
        end = str(item["endDate"])
        parse_jalali(end)
        if end < start:
            raise ValueError("تاریخ پایان تغییر ساعت قبل از شروع است.")
    _text(item, "title")
    if _text(item, "scheduleType", 40) not in {"changed_hours", "remote_work", "delayed_start", "early_close"}:
        raise ValueError("نوع تغییر ساعت نامعتبر است.")
    scope = _text(item, "scope", 40)
    if scope not in {"national", "province", "county", "organization"}:
        raise ValueError("دامنه تغییر ساعت نامعتبر است.")
    if scope in {"province", "county"} and not str(item.get("province", "")).strip():
        raise ValueError("استان تغییر ساعت خالی است.")
    counties = _string_list(item, "counties")
    _string_list(item, "excludedCounties")
    if scope == "county" and not counties:
        raise ValueError("برای تغییر ساعت شهرستانی باید نام شهرستان درج شود.")
    _text(item, "authority")
    if item.get("sourceUrl") and not _HTTPS.match(str(item["sourceUrl"])):
        raise ValueError("نشانی منبع تغییر ساعت HTTPS نیست.")
    if _text(item, "status", 40) not in {"active", "updated", "cancelled"}:
        raise ValueError("وضعیت تغییر ساعت نامعتبر است.")
    for key in ("startTime", "endTime"):
        if item.get(key) and not _TIME.match(str(item[key])):
            raise ValueError(f"{key} نامعتبر است.")


def validate_payloads(holiday_payload: dict[str, Any], work_payload: dict[str, Any], require_baseline: bool = True) -> dict[str, int]:
    if holiday_payload.get("format") != HOLIDAY_FEED_FORMAT:
        raise ValueError("قالب خوراک تعطیلات اشتباه است.")
    if work_payload.get("format") != WORK_SCHEDULE_FEED_FORMAT:
        raise ValueError("قالب خوراک ساعات کاری اشتباه است.")
    holidays = holiday_payload.get("holidays")
    schedules = work_payload.get("schedules")
    if not isinstance(holidays, list) or not isinstance(schedules, list):
        raise ValueError("فهرست خوراک معتبر نیست.")
    holiday_ids: set[str] = set()
    schedule_ids: set[str] = set()
    for item in holidays:
        if not isinstance(item, dict):
            raise ValueError("رکورد تعطیلی معتبر نیست.")
        validate_holiday_item(item)
        if item["id"] in holiday_ids:
            raise ValueError(f"شناسه تعطیلی تکراری است: {item['id']}")
        holiday_ids.add(item["id"])
    for item in schedules:
        if not isinstance(item, dict):
            raise ValueError("رکورد تغییر ساعت معتبر نیست.")
        validate_schedule_item(item)
        if item["id"] in schedule_ids:
            raise ValueError(f"شناسه تغییر ساعت تکراری است: {item['id']}")
        schedule_ids.add(item["id"])
    official_dates = {item["date"] for item in holidays if item.get("type") == "official" and item.get("scope") == "national" and item.get("status") != "cancelled"}
    if require_baseline:
        if len(official_dates) != 26:
            raise ValueError(f"تعطیلات رسمی ۱۴۰۵ ناقص است: {len(official_dates)} از ۲۶")
        national_summer = [i for i in schedules if i.get("id") == "national-work-hours-1405-summer"]
        if len(national_summer) != 1:
            raise ValueError("بازه رسمی ساعت کاری ۷ تا ۱۳ باید دقیقاً یک رکورد باشد.")
        period = national_summer[0]
        if period.get("scheduleType") != "changed_hours" or period.get("date") != "1405-02-26" or period.get("endDate") != "1405-06-15":
            raise ValueError("رکورد بازه‌ای ساعت کاری رسمی معتبر نیست.")
        if not any(i.get("id") == "work-ilam-1405-04-24-early-close-11" for i in schedules):
            raise ValueError("اطلاعیه تاییدشده ایلام در خوراک ساعات کاری وجود ندارد.")
        county_holidays = [
            i for i in holidays
            if i.get("id") == "holiday-ilam-dehloran-1405-04-24"
            and i.get("scope") == "county"
            and i.get("counties") == ["دهلران"]
        ]
        if len(county_holidays) != 1:
            raise ValueError("نمونه تعطیلی شهرستانی دهلران در خوراک وجود ندارد.")
        required_extra = {"holiday-national-1405-04-14-mourning", "holiday-national-1405-04-15-funeral"}
        if not required_extra.issubset(holiday_ids):
            raise ValueError("تعطیلی‌های رسمی موردی ۱۴ و ۱۵ تیر ۱۴۰۵ ناقص است.")
    periodic = sum(1 for item in schedules if item.get("scheduleType") == "changed_hours" and item.get("endDate") and item.get("endDate") != item.get("date"))
    incidents = len(schedules) - periodic
    return {"holidays": len(holidays), "officialHolidayDates": len(official_dates), "schedules": len(schedules), "periodicSchedules": periodic, "incidentSchedules": incidents}
