from __future__ import annotations

from pathlib import Path
from typing import Any

from .storage import read_json


def load_official_holidays(root: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    raw = read_json(root / "data/official_holidays_1405.json", {})
    holidays = raw.get("holidays")
    if not isinstance(holidays, list):
        raise ValueError("فایل تعطیلات رسمی ۱۴۰۵ معتبر نیست.")
    expected = int(raw.get("expectedHolidayDateCount", 0))
    dates = {str(item.get("date")) for item in holidays if isinstance(item, dict)}
    if expected < 1 or len(dates) != expected or len(holidays) != expected:
        raise ValueError(f"تعداد تعطیلات رسمی ۱۴۰۵ ناقص است: expected={expected} actual={len(dates)}")
    return [dict(item) for item in holidays], raw


def load_official_work_schedules(root: Path, holiday_dates: set[str]) -> list[dict[str, Any]]:
    del holiday_dates  # ساعت کاری دوره‌ای یک رکورد بازه‌ای است و در UI روی تعطیلات هشدار نمی‌سازد.
    raw = read_json(root / "data/official_work_schedules_1405.json", {})
    ranges = raw.get("ranges")
    if not isinstance(ranges, list) or not ranges:
        raise ValueError("فایل ساعات کاری رسمی ۱۴۰۵ معتبر نیست.")
    result: list[dict[str, Any]] = []
    for item in ranges:
        event = {
            "id": str(item["idPrefix"]),
            "date": str(item["startDate"]),
            "endDate": str(item["endDate"]),
            "title": item["title"],
            "scheduleType": item.get("scheduleType", "changed_hours"),
            "scope": item["scope"],
            "authority": item["authority"],
            "sourceUrl": item["sourceUrl"],
            "publishedAt": item["publishedAt"],
            "status": item.get("status", "active"),
            "startTime": item.get("startTime"),
            "endTime": item.get("endTime"),
            "includedOrganizations": item.get("includedOrganizations", []),
            "excludedOrganizations": item.get("excludedOrganizations", []),
            "note": item.get("note"),
        }
        result.append({k: v for k, v in event.items() if v not in (None, [], "")})
    return result


def official_work_schedule_managed_prefixes(root: Path) -> set[str]:
    raw = read_json(root / "data/official_work_schedules_1405.json", {})
    ranges = raw.get("ranges", [])
    if not isinstance(ranges, list):
        return set()
    return {str(item.get("idPrefix", "")).strip() for item in ranges if isinstance(item, dict) and str(item.get("idPrefix", "")).strip()}


def load_verified_notices(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    raw = read_json(root / "data/verified_notices_1405.json", {})
    notices = raw.get("notices", [])
    if not isinstance(notices, list):
        raise ValueError("فایل اطلاعیه‌های تاییدشده معتبر نیست.")
    holidays: list[dict[str, Any]] = []
    schedules: list[dict[str, Any]] = []
    pending: list[dict[str, Any]] = []
    for item in notices:
        if not isinstance(item, dict):
            continue
        kind = item.get("kind")
        clean = {k: v for k, v in item.items() if k not in {"kind", "county", "reason"}}
        if kind == "holiday":
            holidays.append(clean)
        elif kind == "work_schedule":
            schedules.append(clean)
        elif kind == "pending_county_holiday":
            pending.append({
                "articleUrl": item.get("sourceUrl", ""),
                "source": item.get("authority", "مرجع رسمی"),
                "title": item.get("title", "اطلاعیه شهرستانی"),
                "publishedAt": item.get("publishedAt", ""),
                "reason": item.get("reason", "دامنه شهرستانی پشتیبانی نمی‌شود."),
                "provinceHint": item.get("province"),
                "excerpt": f"شهرستان: {item.get('county', '')} - تاریخ: {item.get('date', '')}",
            })
    return holidays, schedules, pending
