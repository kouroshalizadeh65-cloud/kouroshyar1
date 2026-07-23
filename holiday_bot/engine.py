from __future__ import annotations

import json
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .classify import classify_article
from .config import load_config
from .constants import BOT_VERSION, CLASSIFIER_VERSION, HOLIDAY_FEED_FORMAT, PROVINCES, WORK_SCHEDULE_FEED_FORMAT
from .extract import (
    FetchError, SafeHttpClient, article_content_hash, article_fingerprint, fetch_bing_news_articles,
    fetch_html_index_articles, fetch_irna_archive_articles, fetch_irna_tag_articles,
    fetch_public_channel_articles, fetch_rss_articles,
)
from .models import Article, CancellationDirective, PendingCandidate
from .reconcile import apply_cancellations, merge_semantic_events
from .seeds import (
    load_official_holidays, load_official_work_schedules, load_verified_notices,
    official_work_schedule_managed_prefixes,
)
from .storage import (
    assert_expected_key, load_existing_payload_state, load_private_key, load_revision_floor,
    read_json, revision_floor_json, sign_payload, write_json,
)
from .validate import validate_payloads


class HealthGateError(RuntimeError):
    def __init__(self, message: str, report: dict[str, Any]):
        super().__init__(message)
        self.report = report


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
    if kind == "public_channel":
        return fetch_public_channel_articles(client, source, allowed_domains, mode=mode)
    if kind == "bing_news":
        return fetch_bing_news_articles(client, source, allowed_domains)
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
    active_sources = [
        source for source in config["sources"]
        if mode in source.get("modes", ["current"])
    ]
    workers = max(1, min(int(config.get("fetch_workers", 8)), 16))
    user_agent = config.get("user_agent", f"KouroshYar-Holiday-Bot/{BOT_VERSION}")
    timeout_seconds = int(config.get("timeout_seconds", 20))
    max_response_bytes = int(config.get("max_response_bytes", 2_000_000))
    retry_attempts = int(config.get("http_retry_attempts", 3))
    retry_backoff_seconds = float(config.get("http_retry_backoff_seconds", 2.0))
    retry_max_wait_seconds = float(config.get("http_retry_max_wait_seconds", 30.0))

    def fetch_one(source: dict[str, Any]) -> tuple[dict[str, Any], list[Article]]:
        stat: dict[str, Any] = {
            "source": source["name"], "kind": source["kind"], "status": "ok",
            "province": source.get("province"),
            "coverageRole": source.get("coverage_role"),
            "critical": bool(source.get("critical", False)),
            "fetched": 0, "selected": 0, "skippedOld": 0, "skippedSeen": 0,
            "rechecked": 0, "contentChanged": 0,
            "holidaysPublished": 0, "schedulesPublished": 0, "cancellationsFound": 0, "pending": 0,
        }
        items: list[Article] = []
        client: SafeHttpClient | None = None
        try:
            client = SafeHttpClient(
                user_agent,
                timeout_seconds,
                max_response_bytes,
                retry_attempts=int(source.get("http_retry_attempts", retry_attempts)),
                retry_backoff_seconds=float(source.get("http_retry_backoff_seconds", retry_backoff_seconds)),
                retry_max_wait_seconds=float(source.get("http_retry_max_wait_seconds", retry_max_wait_seconds)),
            )
            items = _fetch_source(client, source, allowed_domains, mode)
            stat["fetched"] = len(items)
        except FetchError as exc:
            stat["status"] = "deferred" if exc.transient else "error"
            stat["error"] = str(exc)[:500]
            stat["errorType"] = exc.category
            stat["transient"] = exc.transient
            stat["statusCode"] = exc.status_code
            stat["attempts"] = exc.attempts
            stat["failedUrl"] = exc.url
        except Exception as exc:
            stat["status"] = "error"
            stat["error"] = str(exc)[:500]
            stat["errorType"] = type(exc).__name__
            stat["transient"] = False
        finally:
            if client is not None:
                stat["http"] = client.telemetry
        return stat, items

    with ThreadPoolExecutor(max_workers=workers, thread_name_prefix="holiday-source") as executor:
        fetched = list(executor.map(fetch_one, active_sources))
    source_stats = [stat for stat, _items in fetched]
    all_articles = [article for _stat, items in fetched for article in items]

    unique_articles = {article.article_url: article for article in all_articles}
    seen_path = root / "data/seen.json"
    seen = read_json(seen_path, {"schema": "kouroshyar-seen-v2", "articles": {}})
    seen_articles: dict[str, Any] = seen.setdefault("articles", {})
    cutoff = started - timedelta(hours=int(config.get("current_lookback_hours", 336)))
    recheck_after = timedelta(hours=int(config.get("content_recheck_hours", 24)))
    stats_by_source = {stat["source"]: stat for stat in source_stats}
    selected: list[Article] = []
    for article in unique_articles.values():
        fingerprint = article_fingerprint(article)
        content_hash = article_content_hash(article)
        previous = seen_articles.get(fingerprint, {})
        stat = stats_by_source.get(article.source_name)
        if mode == "current" and article.published_at < cutoff:
            if stat is not None:
                stat["skippedOld"] += 1
            continue
        same_classifier = previous.get("classifierVersion") == CLASSIFIER_VERSION
        same_content = previous.get("contentHash") == content_hash
        processed_at = None
        try:
            raw_processed = str(previous.get("processedAt", "")).replace("Z", "+00:00")
            processed_at = datetime.fromisoformat(raw_processed) if raw_processed else None
            if processed_at and processed_at.tzinfo is None:
                processed_at = processed_at.replace(tzinfo=timezone.utc)
        except ValueError:
            processed_at = None
        recently_processed = bool(processed_at and started - processed_at.astimezone(timezone.utc) < recheck_after)
        if same_classifier and same_content and recently_processed:
            if stat is not None:
                stat["skippedSeen"] += 1
            continue
        selected.append(article)
        if stat is not None:
            stat["selected"] += 1
            if same_classifier and same_content:
                stat["rechecked"] += 1
            elif previous and not same_content:
                stat["contentChanged"] += 1

    dynamic_holidays: list[dict[str, Any]] = []
    dynamic_schedules: list[dict[str, Any]] = []
    dynamic_cancellations: list[CancellationDirective] = []
    dynamic_pending: list[PendingCandidate] = []
    for article in sorted(selected, key=lambda x: x.published_at):
        classified = classify_article(article, only_year=1405 if mode == "backfill_1405" else None)
        dynamic_holidays.extend(x.to_json() for x in classified.holidays)
        dynamic_schedules.extend(x.to_json() for x in classified.work_schedules)
        dynamic_cancellations.extend(classified.cancellations)
        dynamic_pending.extend(classified.pending)
        stat = stats_by_source.get(article.source_name)
        if stat is not None:
            stat["holidaysPublished"] += len(classified.holidays)
            stat["schedulesPublished"] += len(classified.work_schedules)
            stat["cancellationsFound"] += len(classified.cancellations)
            stat["pending"] += len(classified.pending)
        seen_articles[article_fingerprint(article)] = {
            "url": article.article_url, "title": article.title,
            "publishedAt": article.published_at.astimezone(timezone.utc).isoformat(),
            "processedAt": started.isoformat(), "classifierVersion": CLASSIFIER_VERSION,
            "contentHash": article_content_hash(article),
            "holidays": len(classified.holidays), "schedules": len(classified.work_schedules),
            "cancellations": len(classified.cancellations), "pending": len(classified.pending),
        }

    feed_dir = root / "holiday_feed"
    holiday_payload_path = root / "data/holidays.payload.json"
    work_payload_path = root / "data/working_hours.payload.json"
    holiday_envelope_path = feed_dir / "holidays.json"
    work_envelope_path = feed_dir / "working_hours.json"
    revision_floor_path = root / "data/revision_floor.json"
    revision_floor = load_revision_floor(revision_floor_path)
    holiday_state = load_existing_payload_state(root, holiday_envelope_path, holiday_payload_path, HOLIDAY_FEED_FORMAT)
    work_state = load_existing_payload_state(root, work_envelope_path, work_payload_path, WORK_SCHEDULE_FEED_FORMAT)
    holiday_payload = holiday_state.payload
    work_payload = work_state.payload
    holiday_effective_revision = max(holiday_state.highest_revision, revision_floor.holiday_revision_floor)
    work_effective_revision = max(work_state.highest_revision, revision_floor.working_hours_revision_floor)
    holiday_floor_recovery = holiday_state.highest_revision < revision_floor.holiday_revision_floor
    work_floor_recovery = work_state.highest_revision < revision_floor.working_hours_revision_floor

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
    holidays, holiday_reconcile = merge_semantic_events(
        old_holidays, official_holidays + verified_holidays + dynamic_holidays, "holiday"
    )
    schedules, schedule_reconcile = merge_semantic_events(
        old_schedules, official_schedules + verified_schedules + dynamic_schedules, "work_schedule"
    )
    holidays, schedules, cancellation_stats, unmatched_cancellations = apply_cancellations(
        holidays, schedules, dynamic_cancellations
    )
    for directive in unmatched_cancellations:
        dynamic_pending.append(
            PendingCandidate(
                articleUrl=directive.sourceUrl,
                source=directive.authority,
                title=directive.title,
                publishedAt=directive.publishedAt,
                reason="لغو رسمی شناسایی شد، اما رکورد منطبق قبلی در خوراک پیدا نشد.",
                provinceHint=directive.province,
                excerpt=directive.reason,
            )
        )
    holidays, schedules = _apply_manual_overrides(holidays, schedules, read_json(root / "data/manual_overrides.json", {}))

    old_h_canonical, new_h_canonical = _canonical(old_holidays), _canonical(holidays)
    old_w_canonical, new_w_canonical = _canonical(old_schedules), _canonical(schedules)
    now = started.isoformat()
    force_publish = os.environ.get("KOUROSHYAR_FORCE_PUBLISH", "").strip().lower() in {"1", "true", "yes", "on"}
    holiday_changed = (
        old_h_canonical != new_h_canonical
        or holiday_state.highest_revision < 1
        or holiday_state.restore_required
        or holiday_floor_recovery
        or force_publish
    )
    work_changed = (
        old_w_canonical != new_w_canonical
        or work_state.highest_revision < 1
        or work_state.restore_required
        or work_floor_recovery
        or force_publish
    )
    if holiday_changed:
        holiday_payload = {
            "format": HOLIDAY_FEED_FORMAT,
            "revision": max(1, holiday_effective_revision + 1),
            "generatedAt": now,
            "holidays": holidays,
        }
    if work_changed:
        work_payload = {
            "format": WORK_SCHEDULE_FEED_FORMAT,
            "revision": max(1, work_effective_revision + 1),
            "generatedAt": now,
            "schedules": schedules,
        }

    validation = validate_payloads(holiday_payload, work_payload, require_baseline=True)
    holiday_floor_after = max(revision_floor.holiday_revision_floor, int(holiday_payload["revision"]))
    work_floor_after = max(revision_floor.working_hours_revision_floor, int(work_payload["revision"]))
    floor_payload = revision_floor_json(holiday_floor_after, work_floor_after, now, f"bot-v{BOT_VERSION}")
    pending = _merge_pending(read_json(root / "data/pending.json", []), verified_pending + dynamic_pending)
    failures = [stat for stat in source_stats if stat["status"] != "ok"]
    deferred_failures = [stat for stat in failures if stat["status"] == "deferred"]
    hard_failures = [stat for stat in failures if stat["status"] == "error"]
    empty_sources = [stat for stat in source_stats if stat["status"] == "ok" and stat["fetched"] == 0]
    critical_failures = [stat for stat in failures if stat.get("critical")]
    discovery_success = {
        str(stat.get("province"))
        for stat in source_stats
        if stat.get("coverageRole") == "province_discovery"
        and stat.get("province") in PROVINCES
        and stat["status"] == "ok"
    }
    health_config = config.get("health_gate", {})
    minimum_success_ratio = float(health_config.get("minimum_success_ratio", 0.70))
    minimum_province_coverage = int(health_config.get("minimum_province_coverage", 28))
    success_ratio = (len(source_stats) - len(failures)) / max(1, len(source_stats))
    health_reasons: list[str] = []
    health_reason_details: list[dict[str, Any]] = []
    if critical_failures:
        transient = all(bool(item.get("transient")) for item in critical_failures)
        health_reasons.append("یک یا چند منبع حیاتی قابل دریافت نبود.")
        health_reason_details.append({
            "code": "critical_source_unavailable",
            "transient": transient,
            "sources": [item["source"] for item in critical_failures],
        })
    if success_ratio < minimum_success_ratio:
        transient = bool(failures) and all(bool(item.get("transient")) for item in failures)
        health_reasons.append("نسبت موفقیت منابع از حداقل تعیین‌شده کمتر است.")
        health_reason_details.append({
            "code": "success_ratio_below_minimum",
            "transient": transient,
            "actual": round(success_ratio, 4),
            "minimum": minimum_success_ratio,
        })
    if len(discovery_success) < minimum_province_coverage:
        failed_discovery = [
            item for item in failures
            if item.get("coverageRole") == "province_discovery"
        ]
        transient = bool(failed_discovery) and all(bool(item.get("transient")) for item in failed_discovery)
        health_reasons.append("پوشش جستجوی استانی از حداقل تعیین‌شده کمتر است.")
        health_reason_details.append({
            "code": "province_coverage_below_minimum",
            "transient": transient,
            "actual": len(discovery_success),
            "minimum": minimum_province_coverage,
        })
    health_gate_ok = not health_reasons
    gate_result = "passed"
    if not health_gate_ok:
        gate_result = (
            "deferred_no_publish"
            if health_reason_details and all(bool(item.get("transient")) for item in health_reason_details)
            else "failed_no_publish"
        )
    retry_totals = {
        key: sum(int(stat.get("http", {}).get(key, 0)) for stat in source_stats)
        for key in ("requestAttempts", "retryCount", "rateLimitRetries", "transientHttpRetries", "networkRetries")
    }
    retry_totals["retryWaitSeconds"] = round(sum(float(stat.get("http", {}).get("retryWaitSeconds", 0.0)) for stat in source_stats), 3)
    retry_totals["pageDelaySeconds"] = round(sum(float(stat.get("http", {}).get("pageDelaySeconds", 0.0)) for stat in source_stats), 3)
    source_health = {
        "schema": "kouroshyar-source-health-v3",
        "botVersion": BOT_VERSION,
        "generatedAt": now,
        "mode": mode,
        "attempted": len(source_stats),
        "succeeded": len(source_stats) - len(failures),
        "failed": len(failures),
        "deferred": len(deferred_failures),
        "hardFailed": len(hard_failures),
        "empty": len(empty_sources),
        "successRatio": round(success_ratio, 4),
        "provinceDiscoveryCoverage": len(discovery_success),
        "coveredProvinces": sorted(discovery_success),
        "missingDiscoveryProvinces": sorted(set(PROVINCES) - discovery_success),
        "criticalFailures": critical_failures,
        "retryTotals": retry_totals,
        "healthGate": {
            "ok": health_gate_ok,
            "result": gate_result,
            "minimumSuccessRatio": minimum_success_ratio,
            "minimumProvinceCoverage": minimum_province_coverage,
            "reasons": health_reasons,
            "reasonDetails": health_reason_details,
        },
        "failures": failures,
        "deferredFailures": deferred_failures,
        "hardFailures": hard_failures,
        "emptySources": [
            {"source": item["source"], "kind": item["kind"], "province": item.get("province")}
            for item in empty_sources
        ],
    }
    report = {
        "botVersion": BOT_VERSION, "classifierVersion": CLASSIFIER_VERSION, "mode": mode,
        "startedAt": now, "dryRun": dry_run,
        "officialCalendarSourceSha256": calendar_meta.get("sourceSha256"),
        "sourcesAttempted": len(source_stats), "sourcesSucceeded": len(source_stats) - len(failures), "sourcesFailed": len(failures),
        "sourcesDeferred": len(deferred_failures), "sourcesHardFailed": len(hard_failures),
        "sourceStats": source_stats, "articlesFetchedUnique": len(unique_articles), "articlesProcessed": len(selected),
        "dynamicHolidayCandidates": len(dynamic_holidays), "dynamicWorkScheduleCandidates": len(dynamic_schedules),
        "dynamicCancellationCandidates": len(dynamic_cancellations),
        "dynamicPendingCandidates": len(dynamic_pending), "pendingTotal": len(pending),
        "reconciliation": {
            "holidayDuplicatesCollapsed": holiday_reconcile["duplicatesCollapsed"],
            "holidayCorrectionsApplied": holiday_reconcile["correctionsApplied"],
            "workingHoursDuplicatesCollapsed": schedule_reconcile["duplicatesCollapsed"],
            "workingHoursCorrectionsApplied": schedule_reconcile["correctionsApplied"],
            "cancellationsApplied": cancellation_stats["cancellationsApplied"],
            "unmatchedCancellations": len(unmatched_cancellations),
        },
        "sourceHealth": source_health,
        "healthGatePassed": health_gate_ok,
        "workflowStatus": gate_result,
        "publicationAllowed": health_gate_ok,
        "holidayChanged": holiday_changed, "workingHoursChanged": work_changed,
        "publishForced": force_publish,
        "holidayRevision": holiday_payload["revision"], "workingHoursRevision": work_payload["revision"],
        "revisionFloor": {
            "holidayBefore": revision_floor.holiday_revision_floor,
            "workingHoursBefore": revision_floor.working_hours_revision_floor,
            "holidayAfter": holiday_floor_after,
            "workingHoursAfter": work_floor_after,
            "holidayRecoveryRequired": holiday_floor_recovery,
            "workingHoursRecoveryRequired": work_floor_recovery,
            "sourceUpdatedAt": revision_floor.updated_at,
            "sourceUpdatedBy": revision_floor.updated_by,
        },
        "holidayRecovery": {
            "source": holiday_state.source,
            "highestKnownRevision": holiday_state.highest_revision,
            "currentEnvelopeRevision": holiday_state.current_envelope_revision,
            "currentPayloadRevision": holiday_state.current_payload_revision,
            "restoreRequired": holiday_state.restore_required,
            "historicalCandidates": holiday_state.historical_candidates,
        },
        "workingHoursRecovery": {
            "source": work_state.source,
            "highestKnownRevision": work_state.highest_revision,
            "currentEnvelopeRevision": work_state.current_envelope_revision,
            "currentPayloadRevision": work_state.current_payload_revision,
            "restoreRequired": work_state.restore_required,
            "historicalCandidates": work_state.historical_candidates,
        },
        "validation": validation,
    }

    write_json(root / "reports/source_health.json", source_health)
    write_json(root / "reports/last_run.json", report)
    if not health_gate_ok:
        raise HealthGateError(
            "کنترل سلامت منابع ناموفق بود؛ خوراک منتشر نشد: " + " ".join(health_reasons),
            report,
        )
    if not dry_run:
        write_json(holiday_payload_path, holiday_payload)
        write_json(work_payload_path, work_payload)
        write_json(holiday_envelope_path, sign_payload(holiday_payload, key))
        write_json(work_envelope_path, sign_payload(work_payload, key))
        write_json(revision_floor_path, floor_payload)
        write_json(seen_path, seen)
        write_json(root / "data/pending.json", pending)
    return report
