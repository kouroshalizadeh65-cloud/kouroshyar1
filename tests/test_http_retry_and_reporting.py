from __future__ import annotations

import warnings
from pathlib import Path

import pytest

from holiday_bot.extract import FetchError, SafeHttpClient, _summary_text, fetch_public_channel_articles


class DummyHttpResponse:
    def __init__(self, status_code: int, url: str, body: bytes = b"ok", headers: dict[str, str] | None = None):
        self.status_code = status_code
        self.url = url
        self._body = body
        self.headers = headers or {}
        self.encoding = "utf-8"
        self.apparent_encoding = "utf-8"
        self._content = body
        self._content_consumed = True
        self.closed = False

    def iter_content(self, _size: int):
        yield self._body

    def raise_for_status(self):
        if self.status_code >= 400:
            import requests
            raise requests.HTTPError(f"HTTP {self.status_code}")

    def close(self):
        self.closed = True


class SequenceSession:
    def __init__(self, responses: list[DummyHttpResponse]):
        self.responses = list(responses)
        self.calls = 0

    def get(self, *_args, **_kwargs):
        self.calls += 1
        return self.responses.pop(0)


class PagingClient:
    def __init__(self):
        self.calls: list[str] = []
        self.pauses: list[float] = []

    def get(self, url: str, _allowed: set[str]):
        self.calls.append(url)
        message_id = 100 - len(self.calls)
        html = f'''<html><body>
        <div class="etme_widget_message_wrap" data-post="channel/{message_id}">
          <div class="etme_widget_message_text">اطلاعیه ساعت کاری ادارات</div>
          <a href="/channel/{message_id}">پیوند</a>
        </div></body></html>'''
        return type("Response", (), {"text": html, "url": url})()

    def pause(self, seconds: float):
        self.pauses.append(seconds)


def test_http_429_retries_respect_retry_after_and_collect_telemetry():
    waits: list[float] = []
    client = SafeHttpClient(
        "test-agent",
        retry_attempts=2,
        retry_backoff_seconds=5,
        sleep_func=waits.append,
    )
    client.session = SequenceSession([
        DummyHttpResponse(429, "https://eitaa.com/channel", headers={"Retry-After": "1"}),
        DummyHttpResponse(429, "https://eitaa.com/channel", headers={"Retry-After": "2"}),
        DummyHttpResponse(200, "https://eitaa.com/channel", body=b"done"),
    ])

    response = client.get("https://eitaa.com/channel", {"eitaa.com"})

    assert response._content == b"done"
    assert waits == [1.0, 2.0]
    assert client.telemetry["requestAttempts"] == 3
    assert client.telemetry["retryCount"] == 2
    assert client.telemetry["rateLimitRetries"] == 2
    assert client.telemetry["retryWaitSeconds"] == 3.0


def test_http_429_exhaustion_is_classified_as_transient_rate_limit():
    client = SafeHttpClient("test-agent", retry_attempts=1, sleep_func=lambda _seconds: None)
    client.session = SequenceSession([
        DummyHttpResponse(429, "https://eitaa.com/channel"),
        DummyHttpResponse(429, "https://eitaa.com/channel"),
    ])

    with pytest.raises(FetchError) as caught:
        client.get("https://eitaa.com/channel", {"eitaa.com"})

    error = caught.value
    assert error.transient is True
    assert error.category == "rate_limited"
    assert error.status_code == 429
    assert error.attempts == 2


def test_current_channel_scan_is_shallow_and_backfill_remains_deep():
    source = {
        "name": "کانال رسمی",
        "kind": "public_channel",
        "url": "https://eitaa.com/channel",
        "candidate_terms": ["ساعت کاری"],
        "max_pages": 10,
        "current_max_pages": 2,
        "backfill_max_pages": 5,
        "current_page_delay_seconds": 0.5,
        "backfill_page_delay_seconds": 1.0,
    }
    current_client = PagingClient()
    fetch_public_channel_articles(current_client, source, {"eitaa.com"}, mode="current")
    assert len(current_client.calls) == 2
    assert current_client.pauses == [0.5]

    backfill_client = PagingClient()
    fetch_public_channel_articles(backfill_client, source, {"eitaa.com"}, mode="backfill_1405")
    assert len(backfill_client.calls) == 5
    assert backfill_client.pauses == [1.0, 1.0, 1.0, 1.0]


def test_plain_filename_summary_does_not_trigger_beautifulsoup_locator_warning():
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        assert _summary_text("SOURCE_VALIDATION_BOT_V1_4_0.md") == "SOURCE_VALIDATION_BOT_V1_4_0.md"
