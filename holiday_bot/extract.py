from __future__ import annotations

import hashlib
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from urllib.parse import quote_plus, urljoin, urlparse

import requests
from bs4 import BeautifulSoup
from dateutil import parser as date_parser

from .constants import PERSIAN_MONTHS, TEHRAN_TZ
from .dates import jalali_to_gregorian
from .models import Article
from .text import normalize_text


class FetchError(RuntimeError):
    pass


class SafeHttpClient:
    def __init__(self, user_agent: str, timeout_seconds: int = 20, max_bytes: int = 2_000_000):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": user_agent,
            "Accept": "text/html,application/rss+xml,application/xml;q=0.9,*/*;q=0.8",
        })
        self.timeout_seconds = timeout_seconds
        self.max_bytes = max_bytes

    def get(self, url: str, allowed_domains: set[str]) -> requests.Response:
        parsed = urlparse(url)
        if parsed.scheme != "https" or not parsed.hostname:
            raise FetchError(f"only HTTPS sources are allowed: {url}")
        if not any(parsed.hostname == d or parsed.hostname.endswith(f".{d}") for d in allowed_domains):
            raise FetchError(f"source domain is not allowlisted: {parsed.hostname}")
        response = self.session.get(url, timeout=self.timeout_seconds, allow_redirects=True, stream=True)
        final = urlparse(response.url)
        if final.scheme != "https" or not final.hostname or not any(
            final.hostname == d or final.hostname.endswith(f".{d}") for d in allowed_domains
        ):
            raise FetchError(f"redirect left allowlisted domains: {response.url}")
        response.raise_for_status()
        content = bytearray()
        for chunk in response.iter_content(64 * 1024):
            content.extend(chunk)
            if len(content) > self.max_bytes:
                raise FetchError(f"response too large: {url}")
        response._content = bytes(content)
        response._content_consumed = True
        if not response.encoding or response.encoding.lower() in {"iso-8859-1", "latin-1"}:
            response.encoding = response.apparent_encoding or "utf-8"
        return response


def parse_published(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    normalized = normalize_text(value)
    # IRNA sometimes exposes Jalali text instead of ISO metadata.
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
        items.append({"title": _rss_text(node, ("title",)), "link": link,
                      "summary": _rss_text(node, ("description", "summary", "content")),
                      "published": _rss_text(node, ("pubdate", "published", "updated", "date"))})
    return items


def _candidate(text: str, terms: tuple[str, ...]) -> bool:
    normalized = normalize_text(text)
    return any(term in normalized for term in terms)


def fetch_rss_articles(client: SafeHttpClient, source: dict, allowed_domains: set[str]) -> list[Article]:
    response = client.get(source["url"], allowed_domains)
    try:
        entries = _parse_rss_items(response.content)
    except ET.ParseError as exc:
        raise FetchError(f"invalid RSS/XML: {source['url']}") from exc
    terms = tuple(source.get("candidate_terms", ("تعطیل", "ساعت کاری", "ساعات کاری", "پایان کار", "آغاز به کار", "دورکار", "کاهش ساعت", "تعجیل")))
    result: list[Article] = []
    for entry in entries[: int(source.get("max_items", 80))]:
        link, title = str(entry.get("link", "")).strip(), normalize_text(entry.get("title", ""))
        if not link or not title or not _candidate(f"{title} {entry.get('summary', '')}", terms):
            continue
        body = normalize_text(entry.get("summary", ""))
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


def article_fingerprint(article: Article) -> str:
    return hashlib.sha256(article.article_url.encode("utf-8")).hexdigest()[:24]
