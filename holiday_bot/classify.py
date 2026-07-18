from __future__ import annotations

import hashlib
import re
from datetime import timezone

from .constants import (
    DEFINITIVE_HOLIDAY_TERMS, NEGATION_TERMS, OFFICIAL_AUTHORITY_TERMS, PROVINCES, WORK_TERMS,
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


def _stable_id(prefix: str, date: str, scope: str, province: str | None, article_url: str, suffix: str = "") -> str:
    digest = hashlib.sha256(f"{article_url}|{date}|{scope}|{province or ''}|{suffix}".encode("utf-8")).hexdigest()[:12]
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
    if article.source_kind.startswith("irna") and province:
        return f"مرجع رسمی اعلام‌شده در خبر ایرنا - استان {province}"
    if "پایگاه اطلاع رسانی دولت" in text or "dolat.ir" in article.article_url:
        return "پایگاه اطلاع‌رسانی دولت"
    return article.source_name


def _scope(text: str, article: Article, province: str | None) -> tuple[str | None, str | None]:
    if province:
        return "province", province
    national_markers = (
        "سراسر کشور", "کل کشور", "در کشور", "دستگاه های اجرایی", "ادارات کشور",
        "سازمان اداری و استخدامی کشور", "هیئت دولت", "پایگاه اطلاع رسانی دولت",
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
        ("ادارات", "ادارات"), ("دستگاه های اجرایی", "دستگاه‌های اجرایی"),
        ("بانک ها", "بانک‌ها"), ("شرکت های بیمه", "شرکت‌های بیمه"),
        ("موسسات عمومی", "مؤسسات عمومی"), ("واحدهای قضایی", "واحدهای قضایی"),
    )
    for pattern, label in mappings:
        if pattern in text and label not in result:
            result.append(label)
    return result


def _county_names(text: str) -> list[str]:
    names: list[str] = []
    for value in re.findall(r"شهرستان(?: های)?\s+([آ-یA-Za-z]+)", text):
        value = value.strip()
        if value not in {"های", "استان", "یاد", "مذکور"} and value not in names:
            names.append(value)
    return names


def _is_partial_geography(text: str) -> bool:
    partial = any(term in text for term in ("شهرستان", "منطقه", "بخش ", "جزیره", "روستا"))
    whole = any(term in text for term in ("تمام استان", "همه استان", "سراسر استان", "کل استان", "ادارات استان"))
    return partial and not whole


def _schedule_type(text: str) -> str:
    if "دورکار" in text:
        return "remote_work"
    if any(term in text for term in ("با تاخیر", "با تأخیر", "آغاز با تاخیر", "دیرتر آغاز", "شروع با تاخیر")):
        return "delayed_start"
    if any(term in text for term in ("تعجیل در پایان", "زودتر", "پایان وقت", "پایان کار", "بسته می شوند", "بسته می‌شوند")):
        return "early_close"
    return "changed_hours"


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


def classify_article(article: Article, only_year: int | None = None) -> ClassificationResult:
    result = ClassificationResult()
    text = normalize_text(article.combined_text)
    if not text:
        return result
    province = _province(text, article.province_hint)
    if any(term in text for term in NEGATION_TERMS):
        result.pending.append(_pending(article, "متن دارای تکذیب، شایعه، احتمال یا لغو است و خودکار منتشر نشد.", province))
        return result

    dates = extract_jalali_dates(text, article.published_at, only_year=only_year)
    start_date, end_date = extract_jalali_range(text, article.published_at, only_year=only_year)
    if start_date and start_date not in dates:
        dates.insert(0, start_date)
    scope, scoped_province = _scope(text, article, province)
    authority = _authority(article, text, province)
    published = article.published_at.astimezone(timezone.utc).isoformat()
    included = _included(text)
    excluded = _excluded(text)
    official_authority = _has_official_authority(article, text)

    # Schedule extraction is independent from holiday extraction, allowing mixed notices.
    has_work_signal = any(term in text for term in WORK_TERMS)
    start_time, end_time = extract_times(text)
    schedule_type = _schedule_type(text)
    if has_work_signal:
        if not dates:
            result.pending.append(_pending(article, "تغییر ساعت قطعی به نظر می‌رسد اما تاریخ قابل اتکا استخراج نشد.", province))
        elif scope is None:
            result.pending.append(_pending(article, "تغییر ساعت شناسایی شد اما محدوده سراسری یا استانی روشن نیست.", province))
        elif not official_authority:
            result.pending.append(_pending(article, "مرجع رسمی تصمیم در متن خبر به‌طور قابل اتکا شناسایی نشد.", province))
        elif not (start_time or end_time or schedule_type in {"remote_work", "delayed_start", "early_close"}):
            result.pending.append(_pending(article, "تغییر ساعت شناسایی شد اما ساعت یا نوع تغییر روشن نیست.", province))
        else:
            # Mixed county/province wording such as "دهلران تعطیل، دیگر شهرستان‌ها ساعت 11".
            counties = _county_names(text)
            schedule_excluded = list(excluded)
            if "دیگر شهرستان های استان" in text and counties:
                for county in counties:
                    label = f"شهرستان {county}"
                    if label not in schedule_excluded:
                        schedule_excluded.append(label)
            for date_value in sorted(set(dates)):
                result.work_schedules.append(WorkScheduleEvent(
                    id=_stable_id("work", date_value, scope, scoped_province, article.article_url, schedule_type),
                    date=date_value,
                    endDate=end_date if end_date and date_value == start_date else None,
                    title=article.title,
                    scheduleType=schedule_type,
                    scope=scope,
                    province=scoped_province,
                    authority=authority,
                    sourceUrl=article.article_url,
                    publishedAt=published,
                    startTime=start_time,
                    endTime=end_time,
                    includedOrganizations=included,
                    excludedOrganizations=schedule_excluded,
                    note="استخراج خودکار از اطلاعیه رسمی؛ متن منبع در جزئیات قابل مراجعه است.",
                ))
                if end_date:
                    break

    # "زودتر تعطیل" is a work-hours change, not a full-day holiday.
    full_day_signal = any(term in text for term in DEFINITIVE_HOLIDAY_TERMS)
    early_only = any(term in text for term in ("زودتر تعطیل", "تعطیلی زودهنگام", "تعجیل در پایان")) and not any(
        term in text for term in ("تعطیل است", "تعطیل خواهد بود", "تعطیل اعلام شد")
    )
    if full_day_signal and not early_only:
        if not dates:
            result.pending.append(_pending(article, "تعطیلی قطعی به نظر می‌رسد اما تاریخ قابل اتکا استخراج نشد.", province))
        elif scope is None:
            result.pending.append(_pending(article, "تعطیلی شناسایی شد اما محدوده سراسری یا استانی روشن نیست.", province))
        elif not official_authority:
            result.pending.append(_pending(article, "مرجع رسمی تصمیم در متن خبر به‌طور قابل اتکا شناسایی نشد.", province))
        elif _is_partial_geography(text):
            result.pending.append(_pending(article, "تعطیلی فقط شهرستان/منطقه را پوشش می‌دهد و نسخه فعلی خوراک دامنه شهرستانی ندارد.", province))
        else:
            event_type = "national_emergency" if scope == "national" else "provincial"
            if any(term in text for term in ("ادارات", "دستگاه های اجرایی")):
                event_type = "administrative"
            if "واحدهای قضایی" in text:
                event_type = "judiciary"
            for date_value in sorted(set(dates)):
                result.holidays.append(HolidayEvent(
                    id=_stable_id("holiday", date_value, scope, scoped_province, article.article_url, event_type),
                    date=date_value,
                    title=article.title,
                    type=event_type,
                    scope=scope,
                    province=scoped_province,
                    authority=authority,
                    sourceUrl=article.article_url,
                    publishedAt=published,
                    includedOrganizations=included,
                    excludedOrganizations=excluded,
                    note="استخراج خودکار از اطلاعیه رسمی؛ متن منبع در جزئیات قابل مراجعه است.",
                ))

    if not result.holidays and not result.work_schedules and not result.pending:
        # Candidate source article, but not enough definitive language.
        if any(term in text for term in ("تعطیل", "ساعت کاری", "ساعات کاری", "دورکار")):
            result.pending.append(_pending(article, "اطلاعیه مرتبط است اما شرایط انتشار خودکار را ندارد.", province))
    return result
