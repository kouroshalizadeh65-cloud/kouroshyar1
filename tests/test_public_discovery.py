from __future__ import annotations

from dataclasses import dataclass

import pytest

from holiday_bot.classify import classify_article
from holiday_bot.extract import (
    FetchError,
    article_content_hash,
    fetch_bing_news_articles,
    fetch_public_channel_articles,
)


@dataclass
class DummyResponse:
    text: str
    url: str
    content: bytes | None = None

    def __post_init__(self) -> None:
        if self.content is None:
            self.content = self.text.encode("utf-8")


class ChannelClient:
    def __init__(self, html: str):
        self.html = html
        self.calls: list[str] = []

    def get(self, url: str, _allowed_domains: set[str]):
        self.calls.append(url)
        return DummyResponse(self.html, url)


class BingClient:
    def __init__(self, xml: str):
        self.xml = xml

    def get(self, url: str, _allowed_domains: set[str]):
        if "bing.com/news/search" in url:
            return DummyResponse(self.xml, url)
        raise FetchError("fixture blocks external article fetch")


def test_official_eitaa_channel_extracts_29_tir_without_manual_seed():
    html = """
    <html><body>
      <div class="etme_widget_message_wrap" data-post="ostandari_ilam/52091">
        <div class="etme_widget_message_text">
          اطلاعیه تغییر ساعت کاری ادارات استان ایلام
          روابط عمومی و امور بین الملل استانداری ایلام اعلام کرد در روز دوشنبه 29 تیرماه 1405
          شهرستان های دهلران و مهران دو ساعت تعجیل در پایان ساعت کاری دارند.
          شهرستان های آبدانان، دره شهر و سیروان یک ساعت تعجیل در پایان ساعت کاری دارند.
          مراکز درمانی، دستگاه های خدمات رسان و نیروهای شیفت گردان مستثنی هستند.
        </div>
        <time datetime="2026-07-20T08:15:00+03:30"></time>
        <a href="/ostandari_ilam/52091">پیوند</a>
      </div>
    </body></html>
    """
    source = {
        "name": "استانداری ایلام - کانال رسمی ایتا",
        "kind": "public_channel",
        "url": "https://eitaa.com/ostandari_ilam",
        "province": "ایلام",
        "candidate_terms": ["ساعت کاری", "تعجیل"],
        "max_pages": 1,
        "max_items": 20,
    }
    articles = fetch_public_channel_articles(ChannelClient(html), source, {"eitaa.com"})
    assert len(articles) == 1
    article = articles[0]
    assert article.source_kind == "official_channel"
    assert article.article_url == "https://eitaa.com/ostandari_ilam/52091"

    result = classify_article(article, 1405)
    assert not result.pending
    assert len(result.work_schedules) == 2
    by_end = {item.endTime: item for item in result.work_schedules}
    assert by_end["11:00"].date == "1405-04-29"
    assert by_end["11:00"].counties == ["دهلران", "مهران"]
    assert by_end["12:00"].counties == ["آبدانان", "دره شهر", "سیروان"]


def test_public_channel_markup_change_fails_loudly():
    source = {
        "name": "کانال رسمی",
        "kind": "public_channel",
        "url": "https://eitaa.com/example",
        "province": "ایلام",
        "max_pages": 1,
    }
    with pytest.raises(FetchError, match="markup"):
        fetch_public_channel_articles(ChannelClient("<html><body>no posts</body></html>"), source, {"eitaa.com"})


def test_bing_discovery_uses_summary_when_external_domain_is_not_allowlisted():
    xml = """<?xml version="1.0" encoding="utf-8"?>
    <rss><channel><item>
      <title>استانداری خوزستان ساعت کاری ادارات را کاهش داد</title>
      <link>https://example.invalid/news/1</link>
      <description>روابط عمومی استانداری خوزستان اعلام کرد روز دوشنبه 29 تیر 1405 پایان کار ادارات ساعت 11 است.</description>
      <pubDate>Mon, 20 Jul 2026 08:00:00 GMT</pubDate>
    </item></channel></rss>"""
    source = {
        "name": "جستجوی تکمیلی خبرهای رسمی - خوزستان",
        "kind": "bing_news",
        "province": "خوزستان",
        "candidate_terms": ["ساعت کاری", "پایان کار"],
        "max_items": 10,
    }
    articles = fetch_bing_news_articles(BingClient(xml), source, {"bing.com"})
    assert len(articles) == 1
    assert articles[0].source_kind == "news_search"
    result = classify_article(articles[0], 1405)
    assert len(result.work_schedules) == 1
    assert result.work_schedules[0].province == "خوزستان"
    assert result.work_schedules[0].endTime == "11:00"


def test_content_hash_changes_when_official_post_is_edited():
    html_a = "اطلاعیه استانداری: پایان کار ادارات ساعت 11 است"
    html_b = "اطلاعیه اصلاحی استانداری: پایان کار ادارات ساعت 12 است"
    from datetime import datetime, timezone
    from holiday_bot.models import Article

    a = Article("source", "official_channel", "https://eitaa.com/x", "https://eitaa.com/x/1", "اطلاعیه", html_a, datetime.now(timezone.utc), "ایلام")
    b = Article("source", "official_channel", "https://eitaa.com/x", "https://eitaa.com/x/1", "اطلاعیه", html_b, datetime.now(timezone.utc), "ایلام")
    assert article_content_hash(a) != article_content_hash(b)
