from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
from typing import Any, Iterable
from urllib.parse import urlparse

from .models import CancellationDirective
from .text import normalize_text

_VOLATILE_FIELDS = {
    "id",
    "title",
    "authority",
    "sourceUrl",
    "publishedAt",
    "status",
    "note",
}


def _normalized_list(value: Any) -> tuple[str, ...]:
    if not isinstance(value, list):
        return ()
    items = {normalize_text(str(item)) for item in value if normalize_text(str(item))}
    return tuple(sorted(items))


def _organization_key(item: dict[str, Any]) -> tuple[tuple[str, ...], tuple[str, ...]]:
    return (
        _normalized_list(item.get("includedOrganizations")),
        _normalized_list(item.get("excludedOrganizations")),
    )


def correction_identity(item: dict[str, Any], kind: str) -> tuple[Any, ...]:
    """Broader identity used only for explicit official corrections."""
    if kind not in {"holiday", "work_schedule"}:
        raise ValueError(f"unknown event kind: {kind}")
    return (
        kind,
        str(item.get("date", "")),
        str(item.get("scope", "")),
        normalize_text(str(item.get("province", ""))),
        _normalized_list(item.get("counties")),
        _normalized_list(item.get("excludedCounties")),
    )


def semantic_identity(item: dict[str, Any], kind: str) -> tuple[Any, ...]:
    """Return the stable decision identity, intentionally excluding source and changed time values.

    The identity is broad enough for a later official correction to replace an earlier decision,
    while county groups and organization coverage remain distinct.
    """
    if kind not in {"holiday", "work_schedule"}:
        raise ValueError(f"unknown event kind: {kind}")
    return (
        kind,
        str(item.get("date", "")),
        str(item.get("endDate", "")) if kind == "work_schedule" else "",
        str(item.get("scope", "")),
        normalize_text(str(item.get("province", ""))),
        _normalized_list(item.get("counties")),
        _normalized_list(item.get("excludedCounties")),
        _organization_key(item),
    )


def _meaningful_content(item: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in item.items():
        if key in _VOLATILE_FIELDS:
            continue
        if isinstance(value, list):
            result[key] = list(_normalized_list(value))
        else:
            result[key] = value
    return result


def _published_at(item: dict[str, Any]) -> datetime:
    raw = str(item.get("publishedAt", "")).strip()
    if not raw:
        return datetime.min.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)


def _source_priority(item: dict[str, Any]) -> int:
    authority = normalize_text(str(item.get("authority", "")))
    url = str(item.get("sourceUrl", ""))
    host = (urlparse(url).hostname or "").lower()
    if any(term in authority for term in ("استانداری", "فرمانداری", "سازمان اداری و استخدامی", "هیئت دولت")):
        return 40
    if host.endswith("dolat.ir") or "portal-" in host or "ostan" in host or "standardari" in host:
        return 35
    if host.endswith("irna.ir"):
        return 25
    if url.startswith("https://"):
        return 10
    return 0


def _prefer_incoming(current: dict[str, Any], incoming: dict[str, Any]) -> bool:
    current_time = _published_at(current)
    incoming_time = _published_at(incoming)
    if incoming_time != current_time:
        return incoming_time > current_time
    return _source_priority(incoming) > _source_priority(current)


def _merge_pair(current: dict[str, Any], incoming: dict[str, Any]) -> tuple[dict[str, Any], bool, bool]:
    """Merge one semantic duplicate.

    Returns (merged, duplicate_collapsed, corrected).
    """
    current_copy = deepcopy(current)
    incoming_copy = deepcopy(incoming)
    content_changed = _meaningful_content(current_copy) != _meaningful_content(incoming_copy)
    prefer_incoming = _prefer_incoming(current_copy, incoming_copy)

    if not prefer_incoming:
        return current_copy, True, False

    preserved_id = str(current_copy.get("id") or incoming_copy.get("id"))
    merged = incoming_copy
    if preserved_id:
        merged["id"] = preserved_id

    corrected = content_changed
    if corrected:
        merged["status"] = "updated"
        previous_note = normalize_text(str(merged.get("note", "")))
        suffix = "تصمیم قبلی با اطلاعیه رسمی جدید اصلاح یا جایگزین شده است."
        merged["note"] = f"{previous_note} {suffix}".strip()
    elif current_copy.get("status") == "cancelled" and incoming_copy.get("status") != "updated":
        # A repeated copy of an older active decision must never revive a cancelled record.
        merged = current_copy
    return merged, True, corrected


def merge_semantic_events(
    existing: Iterable[dict[str, Any]],
    additions: Iterable[dict[str, Any]],
    kind: str,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    by_identity: dict[tuple[Any, ...], dict[str, Any]] = {}
    id_to_identity: dict[str, tuple[Any, ...]] = {}
    stats = {"duplicatesCollapsed": 0, "correctionsApplied": 0}

    for raw in list(existing) + list(additions):
        if not isinstance(raw, dict) or not raw.get("id"):
            continue
        item = deepcopy(raw)
        item_id = str(item["id"])
        identity = semantic_identity(item, kind)

        # Exact IDs remain authoritative, even if an old version used a slightly different
        # organization description that changes the semantic identity.
        prior_identity = id_to_identity.get(item_id)
        if prior_identity is not None and prior_identity != identity:
            current = by_identity.pop(prior_identity)
            merged, collapsed, corrected = _merge_pair(current, item)
            merged_identity = semantic_identity(merged, kind)
            competing = by_identity.get(merged_identity)
            if competing is not None:
                merged, collapsed_again, corrected_again = _merge_pair(competing, merged)
                collapsed = collapsed or collapsed_again
                corrected = corrected or corrected_again
            by_identity[merged_identity] = merged
            id_to_identity[str(merged.get("id", item_id))] = merged_identity
            stats["duplicatesCollapsed"] += int(collapsed)
            stats["correctionsApplied"] += int(corrected)
            continue

        current = by_identity.get(identity)
        if current is None and item.get("status") == "updated":
            correction_matches = [
                (candidate_identity, candidate)
                for candidate_identity, candidate in by_identity.items()
                if correction_identity(candidate, kind) == correction_identity(item, kind)
                and candidate.get("status") != "cancelled"
            ]
            if len(correction_matches) == 1:
                old_identity, current = correction_matches[0]
                by_identity.pop(old_identity)
        if current is None:
            by_identity[identity] = item
            id_to_identity[item_id] = identity
            continue

        merged, collapsed, corrected = _merge_pair(current, item)
        merged_identity = semantic_identity(merged, kind)
        competing = by_identity.get(merged_identity)
        if competing is not None and competing is not current:
            merged, collapsed_again, corrected_again = _merge_pair(competing, merged)
            collapsed = collapsed or collapsed_again
            corrected = corrected or corrected_again
        by_identity[merged_identity] = merged
        id_to_identity[str(merged.get("id", item_id))] = merged_identity
        stats["duplicatesCollapsed"] += int(collapsed)
        stats["correctionsApplied"] += int(corrected)

    result = sorted(
        by_identity.values(),
        key=lambda x: (str(x.get("date", "")), str(x.get("id", ""))),
    )
    return result, stats


def _directive_matches(item: dict[str, Any], directive: CancellationDirective) -> bool:
    if str(item.get("date", "")) != directive.date:
        return False
    if str(item.get("scope", "")) != directive.scope:
        return False
    if normalize_text(str(item.get("province", ""))) != normalize_text(directive.province or ""):
        return False
    if _normalized_list(item.get("counties")) != _normalized_list(directive.counties):
        return False
    if _normalized_list(item.get("excludedCounties")) != _normalized_list(directive.excludedCounties):
        return False
    directive_orgs = set(_normalized_list(directive.includedOrganizations))
    item_orgs = set(_normalized_list(item.get("includedOrganizations")))
    if directive_orgs and item_orgs and not directive_orgs.issubset(item_orgs):
        return False
    return True


def apply_cancellations(
    holidays: list[dict[str, Any]],
    schedules: list[dict[str, Any]],
    directives: Iterable[CancellationDirective],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, int], list[CancellationDirective]]:
    holiday_result = deepcopy(holidays)
    schedule_result = deepcopy(schedules)
    applied = 0
    unmatched: list[CancellationDirective] = []

    for directive in directives:
        matched = False
        targets: list[list[dict[str, Any]]] = []
        if directive.target in {"holiday", "both"}:
            targets.append(holiday_result)
        if directive.target in {"work_schedule", "both"}:
            targets.append(schedule_result)
        for records in targets:
            for item in records:
                if not _directive_matches(item, directive):
                    continue
                if _published_at(item) > datetime.fromisoformat(directive.publishedAt.replace("Z", "+00:00")):
                    continue
                item["status"] = "cancelled"
                item["title"] = directive.title
                item["authority"] = directive.authority
                item["sourceUrl"] = directive.sourceUrl
                item["publishedAt"] = directive.publishedAt
                item["note"] = directive.reason or "تصمیم قبلی با اطلاعیه رسمی لغو شده است."
                matched = True
                applied += 1
        if not matched:
            unmatched.append(directive)

    return holiday_result, schedule_result, {"cancellationsApplied": applied}, unmatched
