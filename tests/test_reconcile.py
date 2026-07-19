from holiday_bot.models import CancellationDirective
from holiday_bot.reconcile import apply_cancellations, merge_semantic_events


def _schedule(**overrides):
    item = {
        "id": "work-ilam-1405-04-30-test",
        "date": "1405-04-30",
        "title": "پایان کار ادارات دهلران ساعت ۱۱",
        "scheduleType": "early_close",
        "scope": "county",
        "province": "ایلام",
        "counties": ["دهلران"],
        "authority": "استانداری ایلام",
        "sourceUrl": "https://www.portal-il.ir/notice/1",
        "publishedAt": "2026-07-20T08:00:00+00:00",
        "status": "active",
        "startTime": "07:00",
        "endTime": "11:00",
        "includedOrganizations": ["ادارات"],
    }
    item.update(overrides)
    return item


def test_same_decision_from_two_sources_is_collapsed():
    direct = _schedule()
    media = _schedule(
        id="work-ilam-duplicate-media",
        sourceUrl="https://www.irna.ir/news/999",
        authority="مرجع رسمی اعلام‌شده در خبر ایرنا - استان ایلام",
        publishedAt="2026-07-20T08:00:00+00:00",
    )
    merged, stats = merge_semantic_events([], [media, direct], "work_schedule")
    assert len(merged) == 1
    assert merged[0]["sourceUrl"] == direct["sourceUrl"]
    assert stats["duplicatesCollapsed"] == 1


def test_newer_correction_replaces_time_and_preserves_id():
    current = _schedule()
    correction = _schedule(
        id="new-url-derived-id",
        title="اصلاحیه پایان کار ادارات دهلران ساعت ۱۲",
        sourceUrl="https://www.portal-il.ir/notice/2",
        publishedAt="2026-07-20T09:00:00+00:00",
        endTime="12:00",
        status="updated",
    )
    merged, stats = merge_semantic_events([current], [correction], "work_schedule")
    assert len(merged) == 1
    assert merged[0]["id"] == current["id"]
    assert merged[0]["endTime"] == "12:00"
    assert merged[0]["status"] == "updated"
    assert stats["correctionsApplied"] == 1


def test_official_cancellation_marks_matching_record_cancelled():
    current = _schedule()
    directive = CancellationDirective(
        target="work_schedule",
        date="1405-04-30",
        scope="county",
        province="ایلام",
        counties=["دهلران"],
        title="لغو کاهش ساعت کاری دهلران",
        authority="استانداری ایلام",
        sourceUrl="https://www.portal-il.ir/notice/3",
        publishedAt="2026-07-20T10:00:00+00:00",
        reason="لغو رسمی تصمیم قبلی",
    )
    holidays, schedules, stats, unmatched = apply_cancellations([], [current], [directive])
    assert holidays == []
    assert schedules[0]["status"] == "cancelled"
    assert schedules[0]["sourceUrl"] == directive.sourceUrl
    assert stats["cancellationsApplied"] == 1
    assert unmatched == []


def test_explicit_correction_can_replace_organization_wording_change():
    current = _schedule(includedOrganizations=["ادارات"])
    correction = _schedule(
        id="corrected-org-list",
        title="اصلاحیه ساعت کاری ادارات و بانک‌ها",
        sourceUrl="https://www.portal-il.ir/notice/4",
        publishedAt="2026-07-20T11:00:00+00:00",
        endTime="12:00",
        includedOrganizations=["ادارات", "بانک‌ها"],
        status="updated",
    )
    merged, stats = merge_semantic_events([current], [correction], "work_schedule")
    assert len(merged) == 1
    assert merged[0]["id"] == current["id"]
    assert merged[0]["includedOrganizations"] == ["ادارات", "بانک‌ها"]
    assert merged[0]["endTime"] == "12:00"
    assert stats["correctionsApplied"] == 1
