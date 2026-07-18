from __future__ import annotations

import hashlib
import re
from datetime import timezone

from .constants import (
    DEFINITIVE_HOLIDAY_TERMS,
    NEGATION_TERMS,
    OFFICIAL_AUTHORITY_TERMS,
    PROVINCES,
    WORK_TERMS,
)
from .dates import extract_jalali_dates, extract_jalali_range, extract_times
from .models import Article, ClassificationResult, HolidayEvent, PendingCandidate, WorkScheduleEvent
from .text import excerpt, normalize_text


_EXCLUDED_PATTERNS = (
    ("دستگاه های خدمات رسان", "دستگاه‌های خدمات‌رسان"),
    ("مراکز درمانی", "مراکز درمانی"),
    ("نیروهای نظامی و انتظامی", "نیروهای نظامی و انتظامی"),
    ("واحدهای عملیاتی", "واحدهای عملیاتی"),
    ("نیروهای شیفت گردان", "نیروهای شیفت‌گردان"),
    ("امدادی", "دستگاه‌های امدادی"),
    ("بانک ها مشمول این تصمیم نیستند", "بانک‌ها"),
)

_COUNTY_STOP_WORDS = {
    "استان",
    "های",
    "یاد",
    "یادشده",
    "مذکور",
    "تابعه",
    "دیگر",
    "سایر",
    "همه",
    "تمام",
}

_CLAUSE_SPLIT = re.compile(r"(?:[.!؟؛]+|\s+(?:همچنین|از سوی دیگر|در حالی که|بر پایه این اطلاعیه|بر این اساس)\s+)")


def _stable_id(
    prefix: str,
    date: str,
    scope: str,
    province: str | None,
    article_url: str,
    suffix: str = "",
) -> str:
    digest = hashlib.sha256(
        f"{article_url}|{date}|{scope}|{province or ''}|{suffix}".encode("utf-8")
    ).hexdigest()[:12]
    p = normalize_text(province or "national").replace(" ", "-")
    return f"{prefix}-{p}-{date}-{digest}"[:120]


def _province(text: str, hint: str | None) -> str | None:
    if hint in PROVINCES:
        return hint
    matches = [name for name in PROVINCES if name in text]
    if not matches:
        return None
    return max(matches, key=len)


def _authority(article: Article, text: str, province: str | None) -> str:
    if "سازمان اداری و استخدامی" in text:
        return "سازمان اداری و استخدامی کشور"
    if province and "استانداری" in text:
        return f"استانداری {province}"
    if province and "فرمانداری" in text:
        return f"فرمانداری شهرستان اعلام‌شده در استان {province}"
    if article.source_kind.startswith("irna") and province:
        return f"مرجع رسمی اعلام‌شده در خبر ایرنا - استان {province}"
    if "پایگاه اطلاع رسانی دولت" in text or "dolat.ir" in article.article_url:
        return "پایگاه اطلاع‌رسانی دولت"
    return article.source_name


def _base_scope(text: str, article: Article, province: str | None) -> tuple[str | None, str | None]:
    if province:
        return "province", province
    national_markers = (
        "سراسر کشور",
        "کل کشور",
        "در کشور",
        "دستگاه های اجرایی",
        "ادارات کشور",
        "سازمان اداری و استخدامی کشور",
        "هیئت دولت",
        "پایگاه اطلاع رسانی دولت",
    )
    if any(marker in text for marker in national_markers) or "dolat.ir" in article.article_url:
        return "national", None
    return None, None


def _has_official_authority(article: Article, text: str) -> bool:
    if "dolat.ir" in article.article_url:
        return True
    return any(term in text for term in OFFICIAL_AUTHORITY_TERMS)


def _excluded(text: str) -> list[str]:
    return [label for pattern, label in _EXCLUDED_PATTERNS if pattern in text]


def _included(text: str) -> list[str]:
    result: list[str] = []
    mappings = (
        ("ادارات", "ادارات"),
        ("اداره ها", "ادارات"),
        ("دستگاه های اجرایی", "دستگاه‌های اجرایی"),
        ("بانک ها", "بانک‌ها"),
        ("شرکت های بیمه", "شرکت‌های بیمه"),
        ("موسسات عمومی", "مؤسسات عمومی"),
        ("واحدهای قضایی", "واحدهای قضایی"),
    )
    for pattern, label in mappings:
        if pattern in text and label not in result:
            result.append(label)
    return result


def _clean_county_name(value: str) -> str | None:
    value = normalize_text(value)
    value = re.sub(r"^(?:شهرستان|شهر)\s+", "", value).strip(" ،,:؛-")
    value = re.sub(
        r"\s+(?:در|روز|فردا|امروز|تعطیل|فعالیت|ادارات|دستگاه|بانک|شرکت|ساعت|با|به|مشمول|مستثنی|پایان|آغاز|کاهش|افزایش)\b.*$",
        "",
        value,
    ).strip(" ،,:؛-")
    if not value or value in _COUNTY_STOP_WORDS or len(value) > 60:
        return None
    if re.search(r"\d", value):
        return None
    return value


def _split_county_fragment(fragment: str) -> list[str]:
    fragment = normalize_text(fragment)
    fragment = re.sub(
        r"\s+(?:در|روز|فردا|امروز|تعطیل|فعالیت|ادارات|دستگاه|بانک|شرکت|ساعت|با|به|مشمول|مستثنی|پایان|آغاز|کاهش|افزایش)\b.*$",
        "",
        fragment,
    )
    parts = re.split(r"\s*(?:،|,| و | یا )\s*", fragment)
    result: list[str] = []
    for raw in parts:
        clean = _clean_county_name(raw)
        if clean and clean not in result:
            result.append(clean)
    return result


def _county_names(text: str) -> list[str]:
    normalized = normalize_text(text)
    result: list[str] = []
    patterns = (
        r"شهرستان(?: های|های)?\s+(.{1,220}?)(?=(?:\s+(?:در|روز|فردا|امروز|تعطیل|فعالیت|ادارات|دستگاه|بانک|شرکت|ساعت|با|به|مشمول|مستثنی|پایان|آغاز|کاهش|افزایش)\b)|[.!؟؛]|$)",
        r"شهرهای\s+(.{1,220}?)(?=(?:\s+(?:در|روز|فردا|امروز|تعطیل|فعالیت|ادارات|دستگاه|بانک|شرکت|ساعت|با|به|مشمول|مستثنی|پایان|آغاز|کاهش|افزایش)\b)|[.!؟؛]|$)",
    )
    for pattern in patterns:
        for match in re.finditer(pattern, normalized):
            for name in _split_county_fragment(match.group(1)):
                if name not in result:
                    result.append(name)
    return result


def _excluded_counties(text: str) -> list[str]:
    normalized = normalize_text(text)
    result: list[str] = []
    for match in re.finditer(
        r"(?:به جز|بجز|غیر از|به استثنای)\s+شهرستان(?: های|های)?\s+(.{1,180}?)(?=(?:\s+(?:در|روز|فردا|امروز|تعطیل|فعالیت|ادارات|دستگاه|بانک|شرکت|ساعت|با|به|مشمول|مستثنی|پایان|آغاز)\b)|[.!؟؛]|$)",
        normalized,
    ):
        for name in _split_county_fragment(match.group(1)):
            if name not in result:
                result.append(name)
    return result


def _decision_clauses(text: str) -> list[str]:
    normalized = normalize_text(text)
    clauses = [part.strip(" ،؛") for part in _CLAUSE_SPLIT.split(normalized) if part.strip(" ،؛")]
    return clauses or [normalized]


def _contains_work_signal(text: str) -> bool:
    return any(term in text for term in WORK_TERMS)


def _contains_full_day_signal(text: str) -> bool:
    full_day_signal = any(term in text for term in DEFINITIVE_HOLIDAY_TERMS)
    early_only = any(
        term in text for term in ("زودتر تعطیل", "تعطیلی زودهنگام", "تعجیل در پایان")
    ) and not any(term in text for term in ("تعطیل است", "تعطیل خواهد بود", "تعطیل اعلام شد"))
    return full_day_signal and not early_only


def _schedule_type(text: str) -> str:
    if "دورکار" in text:
        return "remote_work"
    if any(term in text for term in ("با تاخیر", "با تأخیر", "آغاز با تاخیر", "دیرتر آغاز", "شروع با تاخیر")):
        return "delayed_start"
    if any(
        term in text
        for term in (
            "تعجیل در پایان",
            "زودتر",
            "پایان وقت",
            "پایان کار",
            "بسته می شوند",
            "بسته می‌شوند",
            "کاهش ساعت",
            "کاهش یافت",
        )
    ):
        return "early_close"
    return "changed_hours"


def _event_geography(
    clause: str,
    province: str | None,
    known_counties: list[str],
) -> tuple[str | None, str | None, list[str], list[str]]:
    local_counties = _county_names(clause)
    explicit_exclusions = _excluded_counties(clause)
    other_counties = any(
        marker in clause
        for marker in (
            "دیگر شهرستان های استان",
            "سایر شهرستان های استان",
            "دیگر شهرستانها",
            "سایر شهرستانها",
            "بقیه شهرستان های استان",
        )
    )
    if other_counties and province:
        return "province", province, [], list(dict.fromkeys(known_counties + explicit_exclusions))
    if local_counties and province:
        return "county", province, local_counties, []
    if explicit_exclusions and province:
        return "province", province, [], explicit_exclusions
    if province:
        return "province", province, [], []
    return None, None, [], []


def _pending(article: Article, reason: str, province: str | None) -> PendingCandidate:
    return PendingCandidate(
        articleUrl=article.article_url,
        source=article.source_name,
        title=article.title,
        publishedAt=article.published_at.astimezone(timezone.utc).isoformat(),
        reason=reason,
        provinceHint=province or article.province_hint,
        excerpt=excerpt(article.combined_text),
    )


def _dedupe_holidays(items: list[HolidayEvent]) -> list[HolidayEvent]:
    result: dict[str, HolidayEvent] = {}
    for item in items:
        result[item.id] = item
    return list(result.values())


def _dedupe_schedules(items: list[WorkScheduleEvent]) -> list[WorkScheduleEvent]:
    result: dict[str, WorkScheduleEvent] = {}
    for item in items:
        result[item.id] = item
    return list(result.values())


def classify_article(article: Article, only_year: int | None = None) -> ClassificationResult:
    result = ClassificationResult()
    text = normalize_text(article.combined_text)
    if not text:
        return result
    province = _province(text, article.province_hint)
    if any(term in text for term in NEGATION_TERMS):
        result.pending.append(
            _pending(article, "متن دارای تکذیب، شایعه، احتمال یا لغو است و خودکار منتشر نشد.", province)
        )
        return result

    dates = extract_jalali_dates(text, article.published_at, only_year=only_year)
    start_date, end_date = extract_jalali_range(text, article.published_at, only_year=only_year)
    if start_date and start_date not in dates:
        dates.insert(0, start_date)
    base_scope, base_province = _base_scope(text, article, province)
    authority = _authority(article, text, province)
    published = article.published_at.astimezone(timezone.utc).isoformat()
    official_authority = _has_official_authority(article, text)
    decision_text = normalize_text(article.body) or text
    clauses = _decision_clauses(decision_text)
    if not any(_contains_work_signal(clause) or _contains_full_day_signal(clause) for clause in clauses):
        clauses = _decision_clauses(text)
    known_counties = _county_names(decision_text) or _county_names(text)

    work_clauses = [clause for clause in clauses if _contains_work_signal(clause)]
    if not work_clauses and _contains_work_signal(text):
        work_clauses = [text]

    if work_clauses:
        if not dates:
            result.pending.append(
                _pending(article, "تغییر ساعت قطعی به نظر می‌رسد اما تاریخ قابل اتکا استخراج نشد.", province)
            )
        elif not official_authority:
            result.pending.append(
                _pending(article, "مرجع رسمی تصمیم در متن خبر به‌طور قابل اتکا شناسایی نشد.", province)
            )
        else:
            global_start_time, global_end_time = extract_times(text)
            for clause in work_clauses:
                scope, scoped_province, counties, excluded_counties = _event_geography(
                    clause, province, known_counties
                )
                if scope is None:
                    scope, scoped_province = base_scope, base_province
                if scope is None:
                    result.pending.append(
                        _pending(article, "تغییر ساعت شناسایی شد اما محدوده اجرا روشن نیست.", province)
                    )
                    continue
                schedule_type = _schedule_type(clause)
                start_time, end_time_for_clause = extract_times(clause)
                if len(work_clauses) == 1:
                    start_time = start_time or global_start_time
                    end_time_for_clause = end_time_for_clause or global_end_time
                if not (
                    start_time
                    or end_time_for_clause
                    or schedule_type in {"remote_work", "delayed_start", "early_close"}
                ):
                    result.pending.append(
                        _pending(article, "تغییر ساعت شناسایی شد اما ساعت یا نوع تغییر روشن نیست.", province)
                    )
                    continue
                clause_included = _included(clause) or _included(text)
                clause_excluded = _excluded(text)
                geo_suffix = ",".join(counties or excluded_counties)
                for date_value in sorted(set(dates)):
                    result.work_schedules.append(
                        WorkScheduleEvent(
                            id=_stable_id(
                                "work",
                                date_value,
                                scope,
                                scoped_province,
                                article.article_url,
                                f"{schedule_type}|{geo_suffix}|{start_time}|{end_time_for_clause}",
                            ),
                            date=date_value,
                            endDate=end_date if end_date and date_value == start_date and len(work_clauses) == 1 else None,
                            title=article.title,
                            scheduleType=schedule_type,
                            scope=scope,
                            province=scoped_province,
                            counties=counties,
                            excludedCounties=excluded_counties,
                            authority=authority,
                            sourceUrl=article.article_url,
                            publishedAt=published,
                            startTime=start_time,
                            endTime=end_time_for_clause,
                            includedOrganizations=clause_included,
                            excludedOrganizations=clause_excluded,
                            note="استخراج خودکار از اطلاعیه رسمی؛ محدوده شهرستانی بدون تعمیم به کل استان ثبت شده است.",
                        )
                    )
                    if end_date and len(work_clauses) == 1:
                        break

    holiday_clauses = [clause for clause in clauses if _contains_full_day_signal(clause)]
    if not holiday_clauses and _contains_full_day_signal(text):
        holiday_clauses = [text]

    if holiday_clauses:
        if not dates:
            result.pending.append(
                _pending(article, "تعطیلی قطعی به نظر می‌رسد اما تاریخ قابل اتکا استخراج نشد.", province)
            )
        elif not official_authority:
            result.pending.append(
                _pending(article, "مرجع رسمی تصمیم در متن خبر به‌طور قابل اتکا شناسایی نشد.", province)
            )
        else:
            for clause in holiday_clauses:
                scope, scoped_province, counties, excluded_counties = _event_geography(
                    clause, province, known_counties
                )
                if scope is None:
                    scope, scoped_province = base_scope, base_province
                if scope is None:
                    result.pending.append(
                        _pending(article, "تعطیلی شناسایی شد اما محدوده اجرا روشن نیست.", province)
                    )
                    continue
                event_type = "national_emergency" if scope == "national" else "provincial"
                if any(term in clause for term in ("ادارات", "اداره ها", "دستگاه های اجرایی")):
                    event_type = "administrative"
                if "واحدهای قضایی" in clause:
                    event_type = "judiciary"
                geo_suffix = ",".join(counties or excluded_counties)
                for date_value in sorted(set(dates)):
                    result.holidays.append(
                        HolidayEvent(
                            id=_stable_id(
                                "holiday",
                                date_value,
                                scope,
                                scoped_province,
                                article.article_url,
                                f"{event_type}|{geo_suffix}",
                            ),
                            date=date_value,
                            title=article.title,
                            type=event_type,
                            scope=scope,
                            province=scoped_province,
                            counties=counties,
                            excludedCounties=excluded_counties,
                            authority=authority,
                            sourceUrl=article.article_url,
                            publishedAt=published,
                            includedOrganizations=_included(clause) or _included(text),
                            excludedOrganizations=_excluded(text),
                            note="استخراج خودکار از اطلاعیه رسمی؛ محدوده شهرستانی بدون تعمیم به کل استان ثبت شده است.",
                        )
                    )

    result.holidays = _dedupe_holidays(result.holidays)
    result.work_schedules = _dedupe_schedules(result.work_schedules)

    if not result.holidays and not result.work_schedules and not result.pending:
        if any(term in text for term in ("تعطیل", "ساعت کاری", "ساعات کاری", "دورکار")):
            result.pending.append(
                _pending(article, "اطلاعیه مرتبط است اما شرایط انتشار خودکار را ندارد.", province)
            )
    return result
