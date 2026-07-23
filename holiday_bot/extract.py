from __future__ import annotations

import hashlib
import re
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Callable
from urllib.parse import parse_qs, quote_plus, unquote, urljoin, urlparse
from zoneinfo import ZoneInfo

import requests
from bs4 import BeautifulSoup, Tag
from dateutil import parser as date_parser

from .constants import PERSIAN_MONTHS, TEHRAN_TZ
from .dates import jalali_to_gregorian
from .models import Article
from .text import normalize_text


class FetchError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        category: str = "fetch_error",
        transient: bool = False,
        status_code: int | None = None,
        attempts: int = 1,
        url: str | None = None,
    ):
        super().__init__(message)
        self.category = category
        self.transient = transient
        self.status_code = status_code
        self.attempts = attempts
        self.url = url


def _domain_allowed(hostname: str | None, allowed_domains: set[str]) -> bool:
    if not hostname:
        return False
    hostname = hostname.lower().strip(".")
    return any(hostname == d or hostname.endswith(f".{d}") for d in allowed_domains)


class SafeHttpClient:
    def __init__(
        self,
        user_agent: str,
        timeout_seconds: int = 20,
        max_bytes: int = 2_000_000,
        retry_attempts: int = 3,
        retry_backoff_seconds: float = 2.0,
        retry_max_wait_seconds: float = 30.0,
        sleep_func: Callable[[float], None] = time.sleep,
    ):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": user_agent,
            "Accept": "text/html,application/rss+xml,application/xml;q=0.9,*/*;q=0.8",
        })
        self.timeout_seconds = timeout_seconds
        self.max_bytes = max_bytes
        self.retry_attempts = max(0, min(int(retry_attempts), 6))
        self.retry_backoff_seconds = max(0.0, float(retry_backoff_seconds))
        self.retry_max_wait_seconds = max(0.0, float(retry_max_wait_seconds))
        self._sleep = sleep_func
        self._telemetry: dict[str, float | int] = {
            "requestAttempts": 0,
            "retryCount": 0,
            "rateLimitRetries": 0,
            "transientHttpRetries": 0,
            "networkRetries": 0,
            "retryWaitSeconds": 0.0,
            "pageDelaySeconds": 0.0,
        }

    @property
    def telemetry(self) -> dict[str, float | int]:
        result = dict(self._telemetry)
        result["retryWaitSeconds"] = round(float(result["retryWaitSeconds"]), 3)
        result["pageDelaySeconds"] = round(float(result["pageDelaySeconds"]), 3)
        return result

    def pause(self, seconds: float) -> None:
        seconds = max(0.0, float(seconds))
        if seconds <= 0:
            return
        self._telemetry["pageDelaySeconds"] = float(self._telemetry["pageDelaySeconds"]) + seconds
        self._sleep(seconds)

    def _retry_wait(self, response: requests.Response | None, retry_number: int) -> float:
        if response is not None:
            raw = response.headers.get("Retry-After", "").strip()
            if raw:
                try:
                    return min(self.retry_max_wait_seconds, max(0.0, float(raw)))
                except ValueError:
                    try:
                        retry_at = parsedate_to_datetime(raw)
                        if retry_at.tzinfo is None:
                            retry_at = retry_at.replace(tzinfo=timezone.utc)
                        seconds = (retry_at.astimezone(timezone.utc) - datetime.now(timezone.utc)).total_seconds()
                        return min(self.retry_max_wait_seconds, max(0.0, seconds))
                    except (TypeError, ValueError, OverflowError):
                        pass
        fallback = self.retry_backoff_seconds * (2 ** max(0, retry_number - 1))
        return min(self.retry_max_wait_seconds, fallback)

    def _record_retry(self, category: str, wait_seconds: float) -> None:
        self._telemetry["retryCount"] = int(self._telemetry["retryCount"]) + 1
        key = {
            "rate_limited": "rateLimitRetries",
            "transient_http": "transientHttpRetries",
            "network": "networkRetries",
        }[category]
        self._telemetry[key] = int(self._telemetry[key]) + 1
        self._telemetry["retryWaitSeconds"] = float(self._telemetry["retryWaitSeconds"]) + wait_seconds
        if wait_seconds > 0:
            self._sleep(wait_seconds)

    def get(self, url: str, allowed_domains: set[str]) -> requests.Response:
        parsed = urlparse(url)
        if parsed.scheme != "https" or not parsed.hostname:
            raise FetchError(f"only HTTPS sources are allowed: {url}", category="unsafe_url", url=url)
        if not _domain_allowed(parsed.hostname, allowed_domains):
            raise FetchError(
                f"source domain is not allowlisted: {parsed.hostname}",
                category="domain_not_allowed",
                url=url,
            )

        max_attempts = self.retry_attempts + 1
        for attempt in range(1, max_attempts + 1):
            self._telemetry["requestAttempts"] = int(self._telemetry["requestAttempts"]) + 1
            response: requests.Response | None = None
            try:
                response = self.session.get(
                    url,
                    timeout=self.timeout_seconds,
                    allow_redirects=True,
                    stream=True,
                )
            except requests.RequestException as exc:
                if attempt < max_attempts:
                    wait = self._retry_wait(None, attempt)
                    self._record_retry("network", wait)
                    continue
                raise FetchError(
                    f"network request failed after {attempt} attempts: {url}: {exc}",
                    category="network",
                    transient=True,
                    attempts=attempt,
                    url=url,
                ) from exc

            final = urlparse(response.url)
            if final.scheme != "https" or not _domain_allowed(final.hostname, allowed_domains):
                response.close()
                raise FetchError(
                    f"redirect left allowlisted domains: {response.url}",
                    category="unsafe_redirect",
                    attempts=attempt,
                    url=url,
                )

            status = int(response.status_code)
            transient_category = "rate_limited" if status == 429 else "transient_http" if 500 <= status <= 599 else None
            if transient_category is not None:
                if attempt < max_attempts:
                    wait = self._retry_wait(response, attempt)
                    response.close()
                    self._record_retry(transient_category, wait)
                    continue
                response.close()
                raise FetchError(
                    f"HTTP {status} after {attempt} attempts: {url}",
                    category=transient_category,
                    transient=True,
                    status_code=status,
                    attempts=attempt,
                    url=url,
                )

            try:
                response.raise_for_status()
            except requests.HTTPError as exc:
                response.close()
                raise FetchError(
                    f"HTTP {status}: {url}",
                    category="http_error",
                    status_code=status,
                    attempts=attempt,
                    url=url,
                ) from exc

            content = bytearray()
            try:
                for chunk in response.iter_content(64 * 1024):
                    content.extend(chunk)
                    if len(content) > self.max_bytes:
                        response.close()
                        raise FetchError(
                            f"response too large: {url}",
                            category="response_too_large",
                            attempts=attempt,
                            url=url,
                        )
            except requests.RequestException as exc:
                response.close()
                if attempt < max_attempts:
                    wait = self._retry_wait(None, attempt)
                    self._record_retry("network", wait)
                    continue
                raise FetchError(
                    f"response stream failed after {attempt} attempts: {url}: {exc}",
                    category="network",
                    transient=True,
                    attempts=attempt,
                    url=url,
                ) from exc

            response._content = bytes(content)
            response._content_consumed = True
            if not response.encoding or response.encoding.lower() in {"iso-8859-1", "latin-1"}:
                response.encoding = response.apparent_encoding or "utf-8"
            return response

        raise AssertionError("HTTP retry loop ended unexpectedly")


def parse_published(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    normalized = normalize_text(value)
    match = re.search(r"(1[34]\d{2})[-/](\d{1,2})[-/](\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?", normalized)
    if match:
        y, m, d = (int(match.group(i)) for i in (1, 2, 3))
        hour, minute = int(match.group(4) or 12), int(match.group(5) or 0)
        try:
            g = jalali_to_gregorian(y, m, d)
            return datetime(g.year, g.month, g.day, hour, minute, tzinfo=ZoneInfo(TEHRAN_TZ)).astimezone(timezone.utc)
        except ValueError:
            pass
    month_pattern = "|".join(map(re.escape, PERSIAN_MONTHS))
    textual = re.search(
        rf"(?<!\d)(?P<day>[0-3]?\d)\s*(?P<month>{month_pattern})(?:\s*ماه)?\s*(?P<year>1[34]\d{{2}})"
        rf"(?:\s*(?:-|–|،)\s*(?P<hour>[0-2]?\d):(?P<minute>[0-5]\d))?",
        normalized,
    )
    if textual:
        y = int(textual.group("year"))
        m = PERSIAN_MONTHS[textual.group("month")]
        d = int(textual.group("day"))
        hour = int(textual.group("hour") or 12)
        minute = int(textual.group("minute") or 0)
        try:
            g = jalali_to_gregorian(y, m, d)
            return datetime(g.year, g.month, g.day, hour, minute, tzinfo=ZoneInfo(TEHRAN_TZ)).astimezone(timezone.utc)
        except ValueError:
            pass
    try:
        parsed = date_parser.parse(value)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except (ValueError, TypeError, OverflowError):
        return datetime.now(timezone.utc)


def extract_article_body(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "header", "aside", "form"]):
        tag.decompose()
    selectors = ('[itemprop="articleBody"]', ".item-text", ".news-content", ".article-body", "article", "main")
    for selector in selectors:
        node = soup.select_one(selector)
        if node:
            text = normalize_text(" ".join(p.get_text(" ", strip=True) for p in node.find_all(["p", "h2", "li"])))
            if len(text) >= 80:
                return text[:30_000]
    return normalize_text(" ".join(p.get_text(" ", strip=True) for p in soup.find_all("p")))[:30_000]


def _published_from_soup(soup: BeautifulSoup) -> datetime:
    selectors = (
        'meta[property="article:published_time"]', 'meta[itemprop="datePublished"]',
        'meta[name="date"]', "time", ".news-info", ".item-date",
    )
    for selector in selectors:
        node = soup.select_one(selector)
        if node:
            value = node.get("content") or node.get("datetime") or node.get_text(" ", strip=True)
            if value:
                return parse_published(value)
    return datetime.now(timezone.utc)


def _article_from_url(client: SafeHttpClient, source: dict, url: str, allowed_domains: set[str]) -> Article | None:
    response = client.get(url, allowed_domains)
    soup = BeautifulSoup(response.text, "html.parser")
    title_node = soup.select_one("h1") or soup.select_one('[itemprop="headline"]')
    title = normalize_text(title_node.get_text(" ", strip=True) if title_node else "")
    if not title:
        return None
    return Article(
        source_name=source["name"], source_kind=source["kind"], source_url=source.get("url", url),
        article_url=response.url.split("#", 1)[0], title=title, body=extract_article_body(response.text),
        published_at=_published_from_soup(soup), province_hint=source.get("province"),
    )


def _rss_text(node: ET.Element, names: tuple[str, ...]) -> str:
    for child in node.iter():
        local = child.tag.rsplit("}", 1)[-1].lower()
        if local in names and child.text:
            return child.text.strip()
    return ""


def _parse_rss_items(content: bytes) -> list[dict[str, str]]:
    root = ET.fromstring(content)
    items: list[dict[str, str]] = []
    for node in root.iter():
        if node.tag.rsplit("}", 1)[-1].lower() not in {"item", "entry"}:
            continue
        link = ""
        for child in node.iter():
            if child.tag.rsplit("}", 1)[-1].lower() == "link":
                link = (child.attrib.get("href") or child.text or "").strip()
                if link:
                    break
        items.append({
            "title": _rss_text(node, ("title",)),
            "link": link,
            "summary": _rss_text(node, ("description", "summary", "content")),
            "published": _rss_text(node, ("pubdate", "published", "updated", "date")),
        })
    return items


def _candidate(text: str, terms: tuple[str, ...]) -> bool:
    normalized = normalize_text(text)
    return any(term in normalized for term in terms)


def _summary_text(value: str) -> str:
    raw = value or ""
    if "<" not in raw and ">" not in raw:
        return normalize_text(raw)
    return normalize_text(BeautifulSoup(raw, "html.parser").get_text(" ", strip=True))


def fetch_rss_articles(client: SafeHttpClient, source: dict, allowed_domains: set[str]) -> list[Article]:
    response = client.get(source["url"], allowed_domains)
    try:
        entries = _parse_rss_items(response.content)
    except ET.ParseError as exc:
        raise FetchError(f"invalid RSS/XML: {source['url']}") from exc
    terms = tuple(source.get("candidate_terms", ("تعطیل", "ساعت کاری", "ساعات کاری", "پایان کار", "آغاز به کار", "دورکار", "کاهش ساعت", "تعجیل")))
    result: list[Article] = []
    for entry in entries[: int(source.get("max_items", 80))]:
        link = str(entry.get("link", "")).strip()
        title = normalize_text(entry.get("title", ""))
        body = _summary_text(entry.get("summary", ""))
        if not link or not title or not _candidate(f"{title} {body}", terms):
            continue
        published = parse_published(entry.get("published"))
        try:
            full = _article_from_url(client, source, link, allowed_domains)
            if full:
                result.append(full)
                continue
        except Exception:
            pass
        result.append(Article(source["name"], "rss", source["url"], link, title, body, published, source.get("province")))
    return result


def _extract_news_links(html: str, base_url: str, link_regex: str = r"https://www\.irna\.ir/news/\d+") -> list[str]:
    soup = BeautifulSoup(html, "html.parser")
    pattern = re.compile(link_regex)
    links: list[str] = []
    for anchor in soup.find_all("a", href=True):
        url = urljoin(base_url, anchor["href"]).split("#", 1)[0]
        if pattern.search(url):
            links.append(url)
    return list(dict.fromkeys(links))


def fetch_irna_tag_articles(client: SafeHttpClient, source: dict, allowed_domains: set[str]) -> list[Article]:
    response = client.get(source["url"], allowed_domains)
    links = _extract_news_links(response.text, source["url"])
    result: list[Article] = []
    for link in links[: int(source.get("max_items", 80))]:
        try:
            article = _article_from_url(client, source, link, allowed_domains)
            if article:
                result.append(article)
        except Exception:
            continue
    return result


def fetch_irna_archive_articles(client: SafeHttpClient, source: dict, allowed_domains: set[str], year: int) -> list[Article]:
    links: list[str] = []
    for keyword in source.get("keywords", []):
        empty_pages = 0
        for page in range(1, int(source.get("max_pages", 15)) + 1):
            url = f"https://www.irna.ir/archive?kw={quote_plus(keyword)}&ms=0&pi={page}&yr={year}"
            response = client.get(url, allowed_domains)
            page_links = _extract_news_links(response.text, url)
            if not page_links:
                empty_pages += 1
                if empty_pages >= 2:
                    break
            else:
                empty_pages = 0
                links.extend(page_links)
    result: list[Article] = []
    for link in list(dict.fromkeys(links)):
        try:
            article = _article_from_url(client, source, link, allowed_domains)
            if article:
                result.append(article)
        except Exception:
            continue
    return result


def fetch_html_index_articles(client: SafeHttpClient, source: dict, allowed_domains: set[str]) -> list[Article]:
    response = client.get(source["url"], allowed_domains)
    soup = BeautifulSoup(response.text, "html.parser")
    pattern = re.compile(source["link_regex"])
    terms = tuple(source.get("candidate_terms", ("تعطیل", "ساعت کاری", "ساعات کاری", "پایان کار", "دورکار", "کاهش ساعت")))
    links: list[str] = []
    for anchor in soup.find_all("a", href=True):
        hint = normalize_text(anchor.get_text(" ", strip=True))
        if not hint or not _candidate(hint, terms):
            continue
        url = urljoin(source["url"], anchor["href"]).split("#", 1)[0]
        if pattern.search(url):
            links.append(url)
    result: list[Article] = []
    for link in list(dict.fromkeys(links))[: int(source.get("max_items", 100))]:
        try:
            article = _article_from_url(client, source, link, allowed_domains)
            if article:
                result.append(article)
        except Exception:
            continue
    return result


def _message_permalink(node: Tag, channel_url: str) -> str | None:
    channel_path = urlparse(channel_url).path.rstrip("/")
    pattern = re.compile(rf"{re.escape(channel_path)}/(?P<id>\d+)(?:$|[?#])")
    for anchor in node.find_all("a", href=True):
        url = urljoin(channel_url, anchor["href"]).split("#", 1)[0]
        if pattern.search(urlparse(url).path):
            return url
    data_post = node.get("data-post") or node.get("data-message-id")
    if data_post:
        raw = str(data_post).strip().lstrip("/")
        if "/" in raw:
            return f"https://eitaa.com/{raw}"
        return f"{channel_url.rstrip('/')}/{raw}"
    return None


def _message_nodes(soup: BeautifulSoup, channel_url: str) -> list[Tag]:
    selectors = (
        ".etme_widget_message_wrap",
        ".etme_widget_message",
        ".tgme_widget_message_wrap",
        ".tgme_widget_message",
        "article[data-post]",
        "div[data-post]",
    )
    nodes: list[Tag] = []
    for selector in selectors:
        nodes.extend(node for node in soup.select(selector) if isinstance(node, Tag))
    if nodes:
        return list(dict.fromkeys(nodes))

    channel_path = urlparse(channel_url).path.rstrip("/")
    pattern = re.compile(rf"{re.escape(channel_path)}/\d+$")
    for anchor in soup.find_all("a", href=True):
        absolute = urljoin(channel_url, anchor["href"])
        if not pattern.search(urlparse(absolute).path):
            continue
        parent = anchor.find_parent(["article", "section", "div"])
        if isinstance(parent, Tag):
            nodes.append(parent)
    return list(dict.fromkeys(nodes))


def _message_text(node: Tag) -> str:
    selectors = (
        ".etme_widget_message_text",
        ".tgme_widget_message_text",
        ".message_text",
        ".post-text",
        '[data-role="message-text"]',
    )
    for selector in selectors:
        part = node.select_one(selector)
        if part:
            text = normalize_text(part.get_text(" ", strip=True))
            if text:
                return text
    return normalize_text(node.get_text(" ", strip=True))


def _message_published(node: Tag, body: str) -> datetime:
    time_node = node.select_one("time")
    if time_node:
        raw = time_node.get("datetime") or time_node.get("title") or time_node.get_text(" ", strip=True)
        if raw:
            return parse_published(str(raw))
    for attr in ("data-time", "data-date", "data-published"):
        raw = node.get(attr)
        if raw:
            return parse_published(str(raw))
    return parse_published(body)


def _message_id(url: str) -> int | None:
    match = re.search(r"/(\d+)(?:$|[?#])", url)
    return int(match.group(1)) if match else None


def fetch_public_channel_articles(client: SafeHttpClient, source: dict, allowed_domains: set[str], mode: str = "current") -> list[Article]:
    channel_url = str(source["url"]).rstrip("/")
    terms = tuple(source.get("candidate_terms", ("تعطیل", "ساعت کاری", "ساعات کاری", "پایان کار", "آغاز به کار", "دورکار", "کاهش ساعت", "تعجیل")))
    configured_pages = source.get("current_max_pages") if mode == "current" else source.get("backfill_max_pages")
    max_pages = max(1, min(int(configured_pages or source.get("max_pages", 12)), 40))
    page_delay = float(source.get("current_page_delay_seconds", 0.0) if mode == "current" else source.get("backfill_page_delay_seconds", source.get("page_delay_seconds", 0.0)))
    max_items = max(1, min(int(source.get("max_items", 300)), 1000))
    page_url = channel_url
    result: list[Article] = []
    seen_urls: set[str] = set()
    parsed_any_message = False

    for page_index in range(max_pages):
        response = client.get(page_url, allowed_domains)
        soup = BeautifulSoup(response.text, "html.parser")
        nodes = _message_nodes(soup, channel_url)
        if not nodes:
            if not parsed_any_message:
                raise FetchError(f"public channel markup is not recognized: {channel_url}")
            break
        parsed_any_message = True
        page_ids: list[int] = []
        for node in nodes:
            permalink = _message_permalink(node, channel_url)
            if not permalink:
                continue
            message_id = _message_id(permalink)
            if message_id is not None:
                page_ids.append(message_id)
            if permalink in seen_urls:
                continue
            seen_urls.add(permalink)
            body = _message_text(node)
            if not body or not _candidate(body, terms):
                continue
            title = body.split(" | ", 1)[0].strip()
            if len(title) > 180:
                title = title[:177].rstrip() + "..."
            result.append(Article(
                source_name=source["name"],
                source_kind="official_channel",
                source_url=channel_url,
                article_url=permalink,
                title=title or source["name"],
                body=body[:30_000],
                published_at=_message_published(node, body),
                province_hint=source.get("province"),
            ))
            if len(result) >= max_items:
                return result
        if not page_ids:
            break
        oldest = min(page_ids)
        next_url = f"{channel_url}?before={oldest}"
        if next_url == page_url:
            break
        page_url = next_url
        if page_delay > 0 and page_index + 1 < max_pages and hasattr(client, "pause"):
            client.pause(page_delay)
    return result


def _unwrap_bing_link(link: str) -> str:
    parsed = urlparse(link)
    if not parsed.hostname or not parsed.hostname.endswith("bing.com"):
        return link
    params = parse_qs(parsed.query)
    for key in ("url", "u", "r"):
        values = params.get(key)
        if not values:
            continue
        candidate = unquote(values[0])
        if candidate.startswith("a1"):
            candidate = candidate[2:]
        if candidate.startswith("https://"):
            return candidate
    return link


def fetch_bing_news_articles(client: SafeHttpClient, source: dict, allowed_domains: set[str]) -> list[Article]:
    query = str(source.get("query", "")).strip()
    if not query:
        province = str(source.get("province", "")).strip()
        query = f'"{province}" (تعطیلی ادارات OR ساعت کاری ادارات OR کاهش ساعت اداری OR دورکاری ادارات)'
    url = f"https://www.bing.com/news/search?q={quote_plus(query)}&format=rss&setlang=fa"
    response = client.get(url, allowed_domains)
    try:
        entries = _parse_rss_items(response.content)
    except ET.ParseError as exc:
        raise FetchError(f"invalid Bing News RSS/XML: {url}") from exc
    terms = tuple(source.get("candidate_terms", ("تعطیل", "ساعت کاری", "ساعات کاری", "پایان کار", "آغاز به کار", "دورکار", "کاهش ساعت", "تعجیل")))
    result: list[Article] = []
    for entry in entries[: int(source.get("max_items", 50))]:
        title = normalize_text(entry.get("title", ""))
        body = _summary_text(entry.get("summary", ""))
        link = _unwrap_bing_link(str(entry.get("link", "")).strip())
        if not title or not link or not _candidate(f"{title} {body}", terms):
            continue
        published = parse_published(entry.get("published"))
        try:
            full = _article_from_url(client, source, link, allowed_domains)
            if full:
                result.append(full)
                continue
        except Exception:
            pass
        result.append(Article(
            source_name=source["name"],
            source_kind="news_search",
            source_url=url,
            article_url=link,
            title=title,
            body=body,
            published_at=published,
            province_hint=source.get("province"),
        ))
    return result


def article_fingerprint(article: Article) -> str:
    return hashlib.sha256(article.article_url.encode("utf-8")).hexdigest()[:24]


def article_content_hash(article: Article) -> str:
    canonical = normalize_text(f"{article.title}\n{article.body}")
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:24]
