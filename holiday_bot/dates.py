from __future__ import annotations

import calendar
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from .constants import PERSIAN_MONTHS, TEHRAN_TZ
from .text import normalize_text

_MONTH_PATTERN = "|".join(map(re.escape, PERSIAN_MONTHS))


@dataclass(frozen=True)
class JalaliDate:
    year: int
    month: int
    day: int


def gregorian_to_jalali(value: date) -> JalaliDate:
    gy = value.year - 1600
    gm = value.month - 1
    gd = value.day - 1
    g_days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    j_days = (31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29)
    g_day_no = 365 * gy + (gy + 3) // 4 - (gy + 99) // 100 + (gy + 399) // 400
    g_day_no += sum(g_days[:gm])
    if gm > 1 and calendar.isleap(value.year):
        g_day_no += 1
    g_day_no += gd
    j_day_no = g_day_no - 79
    j_np = j_day_no // 12053
    j_day_no %= 12053
    jy = 979 + 33 * j_np + 4 * (j_day_no // 1461)
    j_day_no %= 1461
    if j_day_no >= 366:
        jy += (j_day_no - 1) // 365
        j_day_no = (j_day_no - 1) % 365
    jm = 0
    while jm < 11 and j_day_no >= j_days[jm]:
        j_day_no -= j_days[jm]
        jm += 1
    return JalaliDate(jy, jm + 1, j_day_no + 1)


def jalali_to_gregorian(jy: int, jm: int, jd: int) -> date:
    original = (jy, jm, jd)
    jy -= 979
    jm -= 1
    jd -= 1
    g_days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    j_days = (31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29)
    j_day_no = 365 * jy + (jy // 33) * 8 + ((jy % 33 + 3) // 4)
    j_day_no += sum(j_days[:jm]) + jd
    g_day_no = j_day_no + 79
    gy = 1600 + 400 * (g_day_no // 146097)
    g_day_no %= 146097
    leap = True
    if g_day_no >= 36525:
        g_day_no -= 1
        gy += 100 * (g_day_no // 36524)
        g_day_no %= 36524
        if g_day_no >= 365:
            g_day_no += 1
        else:
            leap = False
    gy += 4 * (g_day_no // 1461)
    g_day_no %= 1461
    if g_day_no >= 366:
        leap = False
        g_day_no -= 1
        gy += g_day_no // 365
        g_day_no %= 365
    gm = 0
    while gm < 11 and g_day_no >= g_days[gm] + (1 if gm == 1 and leap else 0):
        g_day_no -= g_days[gm] + (1 if gm == 1 and leap else 0)
        gm += 1
    result = date(gy, gm + 1, g_day_no + 1)
    if gregorian_to_jalali(result) != JalaliDate(*original):
        raise ValueError("invalid Jalali date")
    return result


def format_jalali(j: JalaliDate) -> str:
    return f"{j.year:04d}-{j.month:02d}-{j.day:02d}"


def parse_jalali(value: str) -> JalaliDate:
    match = re.fullmatch(r"(1[34]\d{2})-(\d{2})-(\d{2})", value)
    if not match:
        raise ValueError(f"invalid Jalali format: {value}")
    j = JalaliDate(*(int(x) for x in match.groups()))
    jalali_to_gregorian(j.year, j.month, j.day)
    return j


def to_jalali_date(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return format_jalali(gregorian_to_jalali(value.astimezone(ZoneInfo(TEHRAN_TZ)).date()))


def _valid_jalali(year: int, month: int, day: int) -> bool:
    try:
        jalali_to_gregorian(year, month, day)
        return True
    except (ValueError, OverflowError):
        return False


def _date_from_parts(day: int, month_name: str, year: int) -> str | None:
    month = PERSIAN_MONTHS[month_name]
    if _valid_jalali(year, month, day):
        return f"{year:04d}-{month:02d}-{day:02d}"
    return None


def extract_jalali_dates(text: str, published_at: datetime, only_year: int | None = None) -> list[str]:
    normalized = normalize_text(text)
    local_published = published_at.astimezone(ZoneInfo(TEHRAN_TZ))
    published_j = gregorian_to_jalali(local_published.date())
    found: set[str] = set()

    for year, month, day in re.findall(r"(?<!\d)(1[34]\d{2})[/-](\d{1,2})[/-](\d{1,2})(?!\d)", normalized):
        y, m, d = int(year), int(month), int(day)
        if _valid_jalali(y, m, d) and (only_year is None or y == only_year):
            found.add(f"{y:04d}-{m:02d}-{d:02d}")

    # day month [year], including "24 تیرماه 1405" and "24 تیر".
    pattern = re.compile(
        rf"(?<!\d)(?P<day>[0-3]?\d)\s*(?P<month>{_MONTH_PATTERN})(?:\s*ماه)?(?:\s*(?P<year>1[34]\d{{2}}))?"
    )
    for match in pattern.finditer(normalized):
        year = int(match.group("year") or published_j.year)
        if only_year is not None and year != only_year:
            continue
        value = _date_from_parts(int(match.group("day")), match.group("month"), year)
        if value:
            found.add(value)

    if not found:
        local_date = local_published.date()
        offset = 2 if "پس فردا" in normalized else 1 if "فردا" in normalized else 0 if "امروز" in normalized else None
        if offset is not None:
            j = gregorian_to_jalali(local_date + timedelta(days=offset))
            if only_year is None or j.year == only_year:
                found.add(format_jalali(j))
    return sorted(found)


def extract_jalali_range(text: str, published_at: datetime, only_year: int | None = None) -> tuple[str | None, str | None]:
    normalized = normalize_text(text)
    local_published = published_at.astimezone(ZoneInfo(TEHRAN_TZ))
    published_j = gregorian_to_jalali(local_published.date())
    range_re = re.compile(
        rf"از(?:\s+روز)?(?:\s+[آ-ی]+)?\s*(?P<sd>[0-3]?\d)\s*(?P<sm>{_MONTH_PATTERN})(?:\s*ماه)?(?:\s*(?P<sy>1[34]\d{{2}}))?"
        rf"\s*(?:تا|الی|لغایت)\s*(?:روز)?(?:\s+[آ-ی]+)?\s*(?P<ed>[0-3]?\d)\s*(?P<em>{_MONTH_PATTERN})(?:\s*ماه)?(?:\s*(?P<ey>1[34]\d{{2}}))?"
    )
    match = range_re.search(normalized)
    if not match:
        return None, None
    sy = int(match.group("sy") or published_j.year)
    ey = int(match.group("ey") or sy)
    if only_year is not None and (sy != only_year or ey != only_year):
        return None, None
    start = _date_from_parts(int(match.group("sd")), match.group("sm"), sy)
    end = _date_from_parts(int(match.group("ed")), match.group("em"), ey)
    if start and end and start <= end:
        return start, end
    return None, None


def extract_times(text: str) -> tuple[str | None, str | None]:
    normalized = normalize_text(text)

    # Explicit ranges: "7 تا 13", "از ساعت 7 تا 13", "7:30 الی 12:00".
    range_patterns = (
        r"(?:از\s*)?(?:ساعت\s*)?(?P<h1>[0-2]?\d)(?::(?P<m1>[0-5]\d))?\s*(?:تا|الی|لغایت|-|–)\s*(?:ساعت\s*)?(?P<h2>[0-2]?\d)(?::(?P<m2>[0-5]\d))?",
        r"آغاز(?:\s+فعالیت|\s+به\s+کار)?\s*(?:از)?\s*ساعت\s*(?P<h1>[0-2]?\d)(?::(?P<m1>[0-5]\d))?.{0,100}?پایان(?:\s+فعالیت|\s+کار)?\s*(?:در)?\s*ساعت\s*(?P<h2>[0-2]?\d)(?::(?P<m2>[0-5]\d))?",
    )
    for pattern in range_patterns:
        match = re.search(pattern, normalized)
        if match:
            h1, h2 = int(match.group("h1")), int(match.group("h2"))
            m1, m2 = int(match.group("m1") or 0), int(match.group("m2") or 0)
            if 0 <= h1 <= 23 and 0 <= h2 <= 23:
                return f"{h1:02d}:{m1:02d}", f"{h2:02d}:{m2:02d}"

    values: list[str] = []
    for hour, minute in re.findall(r"ساعت\s*([0-2]?\d)(?::([0-5]\d))?", normalized):
        h, m = int(hour), int(minute or 0)
        if 0 <= h <= 23:
            values.append(f"{h:02d}:{m:02d}")
    values = list(dict.fromkeys(values))
    if len(values) >= 2:
        return values[0], values[1]
    if len(values) == 1:
        if any(term in normalized for term in ("پایان", "تعجیل", "زودتر", "تا ساعت", "بسته")):
            return None, values[0]
        return values[0], None
    return None, None


def iter_jalali_dates(start: str, end: str) -> list[str]:
    sj, ej = parse_jalali(start), parse_jalali(end)
    current = jalali_to_gregorian(sj.year, sj.month, sj.day)
    last = jalali_to_gregorian(ej.year, ej.month, ej.day)
    if current > last:
        raise ValueError("start date after end date")
    result: list[str] = []
    while current <= last:
        result.append(format_jalali(gregorian_to_jalali(current)))
        current += timedelta(days=1)
    return result


def is_friday(jalali_date: str) -> bool:
    j = parse_jalali(jalali_date)
    return jalali_to_gregorian(j.year, j.month, j.day).weekday() == 4
