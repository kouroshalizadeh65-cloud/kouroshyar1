from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .classify import classify_article
from .config import load_config
from .constants import BOT_VERSION, CLASSIFIER_VERSION, HOLIDAY_FEED_FORMAT, WORK_SCHEDULE_FEED_FORMAT
from .extract import (
    SafeHttpClient, article_fingerprint, fetch_html_index_articles, fetch_irna_archive_articles,
    fetch_irna_tag_articles, fetch_rss_articles,
)
from .models import Article, PendingCandidate
from .seeds import (
    load_official_holidays, load_official_work_schedules, load_verified_notices,
    official_work_schedule_managed_prefixes,
)
from .storage import (
    assert_expected_key, load_existing_payload, load_private_key, read_json, sign_payload, write_json,
)
from .validate import validate_payloads


def _canonical(items: list[dict[str, Any]]) -> str:
    normalized = sorted(items, key=lambda x: (str(x.get("date", "")), str(x.get("id", ""))))
    return json.dumps(normalized, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def _merge_by_id(existing: list[dict[str, Any]], additions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for item in existing + additions:
        if isinstance(item, dict) and item.get("id"):
            merged[str(item["id"])] = dict(item)
    return sorted(merged.values(), key=lambda x: (str(x.get("date", "")), str(x.get("id", ""))))


def _merge_pending(existing: list[Any], additions: list[Any]) -> list[dict[str, Any]]:
    merged: dict[str, dict[str, Any]] = {}
    for raw in existing + additions:
        item = raw.to_json() if isinstance(raw, PendingCandidate) else raw
        if not isinstance(item, dict):
            continue
        key = f"{item.get('articleUrl')}|{item.get('reason')}|{item.get('title')}"
        merged[key] = dict(item)
    return list(merged.values())[-1000:]


def _apply_manual_overrides(holidays: list[dict[str, Any]], schedules: list[dict[str, Any]], overrides: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    holidays = _merge_by_id(holidays, list(overrides.get("upsert_holidays", [])))
    schedules = _merge_by_id(schedules, list(overrides.get("upsert_work_schedules", [])))
    cancel_h = set(map(str, overrides.get("cancel_holiday_ids", [])))
    cancel_w = set(map(str, overrides.get("cancel_work_schedule_ids", [])))
    for item in holidays:
        if item.get("id") in cancel_h:
            item["status"] = "cancelled"
    for item in schedules:
        if item.get("id") in cancel_w:
            item["status"] = "cancelled"
    return holidays, schedules


def _fetch_source(client: SafeHttpClient, source: dict[str, Any], allowed_domains: set[str], mode: str) -> list[Article]:
    kind = source["kind"]
    if kind == "rss":
        return fetch_rss_articles(client, source, allowed_domains)
    if kind == "irna_tag":
        return fetch_irna_tag_articles(client, source, allowed_domains)
    if kind == "irna_archive":
        return fetch_irna_archive_articles(client, source, allowed_domains, year=1405)
    if kind == "html_index":
        return fetch_html_index_articles(client, source, allowed_domains)
    raise ValueError(f"نوع منبع ناشناخته: {kind}")


def run_update(root: Path, config_path: Path, private_key_path: Path, mode: str, dry_run: bool = False) -> dict[str, Any]:
    started = datetime.now(timezone.utc)
    config = load_config(config_path)
    key = load_private_key(private_key_path)
    assert_expected_key(key, config["expected_public_key_b64"])

    official_holidays, calendar_meta = load_official_holidays(root)
    holiday_dates = {item["date"] for item in official_holidays}
    official_schedules = load_official_work_schedules(root, holiday_dates)
    verified_holidays, verified_schedules, verified_pending = load_verified_notices(root)

    allowed_domains = set(config.get("allowed_domains", []))
    client = SafeHttpClient(config.get("user_agent", f"KouroshYar-Holiday-Bot/{BOT_VERSION}"),
                            int(config.get("timeout_seconds", 20)), int(config.get("max_response_bytes", 2_000_000)))
    source_stats: list[dict[str, Any]] = []
    all_articles: list[Article] = []
    for source in config["sources"]:
        if mode not in source.get("modes", ["current"]):
            continue
        stat: dict[str, Any] = {
            "source": source["name"], "kind": source["kind"], "status": "ok",
            "fetched": 0, "selected": 0, "skippedOld": 0, "skippedSeen": 0,
            "holidaysPublished": 0, "schedulesPublished": 0, "pending": 0,
        }
        try:
            items = _fetch_source(client, source, allowed_domains, mode)
            stat["fetched"] = len(items)
            all_articles.extend(items)
        except Exception as exc:
            stat["status"] = "error"
            stat["error"] = str(exc)[:500]
        source_stats.append(stat)

    unique_articles = {article.article_url: article for article in all_articles}
    seen_path = root / "data/seen.json"
    seen = read_json(seen_path, {"schema": "kouroshyar-seen-v2", "articles": {}})
    seen_articles: dict[str, Any] = seen.setdefault("articles", {})
    cutoff = started - timedelta(hours=int(config.get("current_lookback_hours", 168)))
    stats_by_source = {stat["source"]: stat for stat in source_stats}
    selected: list[Article] = []
    for article in unique_articles.values():
        fingerprint = article_fingerprint(article)
        previous = seen_articles.get(fingerprint, {})
        stat = stats_by_source.get(article.source_name)
        if mode == "current" and article.published_at < cutoff:
            if stat is not None:
                stat["skippedOld"] += 1
            continue
        if previous.get("classifierVersion") == CLASSIFIER_VERSION:
            if stat is not None:
                stat["skippedSeen"] += 1
            continue
        selected.append(article)
        if stat is not None:
            stat["selected"] += 1

    dynamic_holidays: list[dict[str, Any]] = []
    dynamic_schedules: list[dict[str, Any]] = []
    dynamic_pending: list[PendingCandidate] = []
    for article in sorted(selected, key=lambda x: x.published_at):
        classified = classify_article(article, only_year=1405 if mode == "backfill_1405" else None)
        dynamic_holidays.extend(x.to_json() for x in classified.holidays)
        dynamic_schedules.extend(x.to_json() for x in classified.work_schedules)
        dynamic_pending.extend(classified.pending)
        stat = stats_by_source.get(article.source_name)
        if stat is not None:
            stat["holidaysPublished"] += len(classified.holidays)
            stat["schedulesPublished"] += len(classified.work_schedules)
            stat["pending"] += len(classified.pending)
        seen_articles[article_fingerprint(article)] = {
            "url": article.article_url, "title": article.title,
            "publishedAt": article.published_at.astimezone(timezone.utc).isoformat(),
            "processedAt": started.isoformat(), "classifierVersion": CLASSIFIER_VERSION,
            "holidays": len(classified.holidays), "schedules": len(classified.work_schedules),
            "pending": len(classified.pending),
        }

    feed_dir = root / "holiday_feed"
    holiday_payload_path = root / "data/holidays.payload.json"
    work_payload_path = root / "data/working_hours.payload.json"
    holiday_envelope_path = feed_dir / "holidays.json"
    work_envelope_path = feed_dir / "working_hours.json"
    holiday_payload = load_existing_payload(holiday_envelope_path, holiday_payload_path, HOLIDAY_FEED_FORMAT)
    work_payload = load_existing_payload(work_envelope_path, work_payload_path, WORK_SCHEDULE_FEED_FORMAT)

    old_holidays = list(holiday_payload.get("holidays", []))
    old_schedules = list(work_payload.get("schedules", []))
    managed_schedule_prefixes = official_work_schedule_managed_prefixes(root)
    # مهاجرت v1.1.1: رکوردهای روزانه قدیمیِ ساعت کاری دوره‌ای حذف و با یک رکورد بازه‌ای جایگزین می‌شوند.
    old_schedules = [
        item for item in old_schedules
        if not any(
            str(item.get("id", "")) == prefix or str(item.get("id", "")).startswith(prefix + "-")
            for prefix in managed_schedule_prefixes
        )
    ]
    holidays = _merge_by_id(old_holidays, official_holidays + verified_holidays + dynamic_holidays)
    schedules = _merge_by_id(old_schedules, official_schedules + verified_schedules + dynamic_schedules)
    holidays, schedules = _apply_manual_overrides(holidays, schedules, read_json(root / "data/manual_overrides.json", {}))

    old_h_canonical, new_h_canonical = _canonical(old_holidays), _canonical(holidays)
    old_w_canonical, new_w_canonical = _canonical(old_schedules), _canonical(schedules)
    now = started.isoformat()
    holiday_changed = old_h_canonical != new_h_canonical or int(holiday_payload.get("revision", 0)) < 1
    work_changed = old_w_canonical != new_w_canonical or int(work_payload.get("revision", 0)) < 1
    if holiday_changed:
        holiday_payload = {"format": HOLIDAY_FEED_FORMAT, "revision": max(1, int(holiday_payload.get("revision", 0)) + 1), "generatedAt": now, "holidays": holidays}
    if work_changed:
        work_payload = {"format": WORK_SCHEDULE_FEED_FORMAT, "revision": max(1, int(work_payload.get("revision", 0)) + 1), "generatedAt": now, "schedules": schedules}

    validation = validate_payloads(holiday_payload, work_payload, require_baseline=True)
    pending = _merge_pending(read_json(root / "data/pending.json", []), verified_pending + dynamic_pending)
    errors = [stat for stat in source_stats if stat["status"] == "error"]
    report = {
        "botVersion": BOT_VERSION, "classifierVersion": CLASSIFIER_VERSION, "mode": mode,
        "startedAt": now, "dryRun": dry_run,
        "officialCalendarSourceSha256": calendar_meta.get("sourceSha256"),
        "sourcesAttempted": len(source_stats), "sourcesSucceeded": len(source_stats) - len(errors), "sourcesFailed": len(errors),
        "sourceStats": source_stats, "articlesFetchedUnique": len(unique_articles), "articlesProcessed": len(selected),
        "dynamicHolidayCandidates": len(dynamic_holidays), "dynamicWorkScheduleCandidates": len(dynamic_schedules),
        "dynamicPendingCandidates": len(dynamic_pending), "pendingTotal": len(pending),
        "holidayChanged": holiday_changed, "workingHoursChanged": work_changed,
        "holidayRevision": holiday_payload["revision"], "workingHoursRevision": work_payload["revision"],
        "validation": validation,
    }

    if not dry_run:
        write_json(holiday_payload_path, holiday_payload)
        write_json(work_payload_path, work_payload)
        write_json(holiday_envelope_path, sign_payload(holiday_payload, key))
        write_json(work_envelope_path, sign_payload(work_payload, key))
        write_json(seen_path, seen)
        write_json(root / "data/pending.json", pending)
        write_json(root / "reports/last_run.json", report)
    return report
