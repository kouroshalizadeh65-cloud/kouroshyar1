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


def test_mixed_ilam_notice_publishes_province_schedule_but_not_county_holiday():
    item = article(
        "موج گرما دهلران را تعطیل کرد؛ ادارات ایلام دو ساعت زودتر بسته می‌شوند",
        "روابط عمومی استانداری ایلام اعلام کرد فعالیت همه اداره‌ها و بانک‌های شهرستان دهلران در روز چهارشنبه 24 تیرماه 1405 تعطیل خواهد بود. فعالیت ادارات، دستگاه های اجرایی، بانک ها و شرکت های بیمه در دیگر شهرستان های استان در ساعت 11 به پایان می رسد. دستگاه های خدمات رسان و مراکز درمانی مستثنی هستند.",
        "https://www.irna.ir/news/86209477/",
        "ایلام",
    )
    result = classify_article(item, 1405)
    assert result.holidays == []
    assert len(result.work_schedules) == 1
    event = result.work_schedules[0]
    assert event.province == "ایلام"
    assert event.scheduleType == "early_close"
    assert event.endTime == "11:00"
    assert any("شهرستان دهلران" == x for x in event.excludedOrganizations)
    assert any("دامنه" in x.reason or "شهرستان" in x.reason for x in result.pending)


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
