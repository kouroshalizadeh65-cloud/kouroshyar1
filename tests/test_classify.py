from datetime import datetime, timezone

from holiday_bot.classify import classify_article
from holiday_bot.models import Article


def article(title: str, body: str, url: str, province: str | None = None) -> Article:
    return Article("test", "irna_tag", "https://www.irna.ir", url, title, body, datetime(2026, 7, 14, 18, tzinfo=timezone.utc), province)


def test_national_official_hours_range_is_extracted():
    item = article(
        "اعلام ساعت کاری جدید ادارات تا 15 شهریور 1405",
        "رئیس سازمان اداری و استخدامی کشور اعلام کرد از شنبه 26 اردیبهشت 1405 تا روز 15 شهریور 1405 ساعت کاری ادارات 7 تا 13 خواهد بود.",
        "https://dolat.ir/detail/481465",
    )
    result = classify_article(item, 1405)
    assert not result.pending
    assert len(result.work_schedules) == 1
    event = result.work_schedules[0]
    assert event.scope == "national"
    assert event.date == "1405-02-26"
    assert event.endDate == "1405-06-15"
    assert (event.startTime, event.endTime) == ("07:00", "13:00")


def test_mixed_ilam_notice_publishes_county_holiday_and_other_counties_schedule():
    item = article(
        "موج گرما دهلران را تعطیل کرد؛ ادارات ایلام دو ساعت زودتر بسته می‌شوند",
        "روابط عمومی استانداری ایلام اعلام کرد فعالیت همه اداره‌ها و بانک‌های شهرستان دهلران در روز چهارشنبه 24 تیرماه 1405 تعطیل خواهد بود. فعالیت ادارات، دستگاه های اجرایی، بانک ها و شرکت های بیمه در دیگر شهرستان های استان در ساعت 11 به پایان می رسد. دستگاه های خدمات رسان و مراکز درمانی مستثنی هستند.",
        "https://www.irna.ir/news/86209477/",
        "ایلام",
    )
    result = classify_article(item, 1405)
    assert len(result.holidays) == 1
    holiday = result.holidays[0]
    assert holiday.scope == "county"
    assert holiday.province == "ایلام"
    assert holiday.counties == ["دهلران"]
    assert holiday.type == "administrative"
    assert "ادارات" in holiday.includedOrganizations

    assert len(result.work_schedules) >= 1
    event = next(item for item in result.work_schedules if item.endTime == "11:00")
    assert event.province == "ایلام"
    assert event.scheduleType == "early_close"
    assert event.scope == "province"
    assert event.excludedCounties == ["دهلران"]
    assert not result.pending


def test_multiple_county_groups_are_kept_separate():
    item = article(
        "کاهش ساعت کاری ادارات ایلام",
        "روابط عمومی استانداری ایلام اعلام کرد روز سه شنبه 23 تیر 1405 پایان کار در شهرستان های دهلران، مهران، آبدانان، دره شهر و سیروان ساعت 11 خواهد بود. همچنین در دیگر شهرستان های استان پایان کار ساعت 12 است.",
        "https://www.irna.ir/news/86208627/",
        "ایلام",
    )
    result = classify_article(item, 1405)
    county = next(event for event in result.work_schedules if event.scope == "county")
    remainder = next(event for event in result.work_schedules if event.scope == "province" and event.excludedCounties)
    assert county.counties == ["دهلران", "مهران", "آبدانان", "دره شهر", "سیروان"]
    assert county.endTime == "11:00"
    assert remainder.excludedCounties == county.counties
    assert remainder.endTime == "12:00"


def test_rumor_or_denial_never_publishes():
    item = article("تکذیب تعطیلی ادارات", "خبر تعطیلی ادارات استان شایعه است و صحت ندارد.", "https://www.irna.ir/news/1", "ایلام")
    result = classify_article(item, 1405)
    assert not result.holidays and not result.work_schedules
    assert result.pending


def test_irna_item_without_identifiable_official_authority_stays_pending():
    item = article(
        "احتمال تغییر ساعت ادارات استان",
        "برخی منابع محلی نوشته‌اند ساعت کاری ادارات ایلام در روز 25 تیر 1405 از 7 تا 11 خواهد بود.",
        "https://www.irna.ir/news/2",
        "ایلام",
    )
    result = classify_article(item, 1405)
    assert not result.holidays and not result.work_schedules
    assert result.pending


def test_relative_early_close_groups_use_official_summer_baseline():
    item = article(
        "اطلاعیه تعجیل در خروج ادارات استان ایلام برای یکشنبه 28 تیر",
        "روابط عمومی و امور بین الملل استانداری ایلام اعلام کرد ساعات کاری ادارات، دستگاه های اجرایی، بانک ها و شرکت های بیمه در روز یکشنبه 28 تیرماه 1405 به شرح زیر است. شهرستان های دهلران، مهران: دو ساعت تعجیل در پایان ساعت کاری. شهرستان های آبدانان، دره شهر، سیروان: یک ساعت تعجیل در پایان ساعت کاری. دستگاه های خدمات رسان، مراکز درمانی، نیروهای نظامی و انتظامی، واحدهای عملیاتی و نیروهای شیفت گردان مستثنی هستند.",
        "https://www.portal-il.ir/archives/arshive1/test-relative-close",
        "ایلام",
    )
    result = classify_article(item, 1405)
    assert not result.pending
    assert len(result.work_schedules) == 2
    by_end = {event.endTime: event for event in result.work_schedules}
    assert by_end["11:00"].counties == ["دهلران", "مهران"]
    assert by_end["12:00"].counties == ["آبدانان", "دره شهر", "سیروان"]
    assert by_end["11:00"].startTime == "07:00"
    assert by_end["12:00"].startTime == "07:00"
    assert "محاسبه" in (by_end["11:00"].note or "")
