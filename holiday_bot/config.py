from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from .constants import EXPECTED_PUBLIC_KEY_B64, PROVINCES


_ALLOWED_KINDS = {
    "rss",
    "irna_tag",
    "irna_archive",
    "html_index",
    "public_channel",
    "bing_news",
}


def load_config(path: Path) -> dict[str, Any]:
    config = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError("فایل تنظیمات معتبر نیست.")
    if config.get("expected_public_key_b64") != EXPECTED_PUBLIC_KEY_B64:
        raise ValueError("کلید عمومی تنظیمات با نسخه نصب‌شده تطابق ندارد.")
    domains = config.get("allowed_domains")
    if not isinstance(domains, list) or not domains:
        raise ValueError("فهرست دامنه‌های مجاز خالی است.")
    if any(not isinstance(item, str) or not item.strip() for item in domains):
        raise ValueError("یکی از دامنه‌های مجاز معتبر نیست.")

    retry_attempts = int(config.get("http_retry_attempts", 3))
    if not 0 <= retry_attempts <= 6:
        raise ValueError("تعداد تلاش مجدد HTTP باید بین صفر و شش باشد.")
    retry_backoff = float(config.get("http_retry_backoff_seconds", 2.0))
    retry_max_wait = float(config.get("http_retry_max_wait_seconds", 30.0))
    if retry_backoff < 0 or retry_max_wait < 0:
        raise ValueError("فاصله تلاش مجدد HTTP نمی‌تواند منفی باشد.")

    sources = config.get("sources")
    if not isinstance(sources, list) or not sources:
        raise ValueError("حداقل یک منبع لازم است.")
    seen_names: set[str] = set()
    discovery_provinces: set[str] = set()
    official_provinces: set[str] = set()
    for source in sources:
        if not isinstance(source, dict) or not source.get("name") or not source.get("kind"):
            raise ValueError("تعریف منبع ناقص است.")
        if source["kind"] not in _ALLOWED_KINDS:
            raise ValueError(f"نوع منبع ناشناخته است: {source['kind']}")
        if source["name"] in seen_names:
            raise ValueError(f"نام منبع تکراری است: {source['name']}")
        seen_names.add(source["name"])
        province = source.get("province")
        if province is not None and province not in PROVINCES:
            raise ValueError(f"استان ناشناخته در تنظیمات: {province}")
        modes = source.get("modes", ["current"])
        if not isinstance(modes, list) or not set(modes).issubset({"current", "backfill_1405"}):
            raise ValueError(f"mode منبع معتبر نیست: {source['name']}")
        if source["kind"] in {"rss", "html_index", "public_channel"} and not source.get("url"):
            raise ValueError(f"نشانی منبع خالی است: {source['name']}")
        if source["kind"] == "html_index" and not source.get("link_regex"):
            raise ValueError(f"الگوی پیوند منبع HTML خالی است: {source['name']}")
        if source["kind"] == "bing_news" and not province:
            raise ValueError(f"منبع جستجوی خبری باید استان داشته باشد: {source['name']}")
        if source["kind"] == "public_channel":
            current_pages = int(source.get("current_max_pages", source.get("max_pages", 12)))
            backfill_pages = int(source.get("backfill_max_pages", source.get("max_pages", 12)))
            if not 1 <= current_pages <= 40 or not 1 <= backfill_pages <= 40:
                raise ValueError(f"تعداد صفحات کانال عمومی معتبر نیست: {source['name']}")
            if current_pages > backfill_pages:
                raise ValueError(f"پایش جاری کانال نباید از backfill عمیق‌تر باشد: {source['name']}")
            for key in ("current_page_delay_seconds", "backfill_page_delay_seconds"):
                if float(source.get(key, 0.0)) < 0:
                    raise ValueError(f"تاخیر صفحه‌بندی منفی است: {source['name']}")
        if source.get("coverage_role") == "province_discovery" and province:
            discovery_provinces.add(province)
        if source.get("verified_official") and province:
            official_provinces.add(province)

    if discovery_provinces != set(PROVINCES):
        missing = sorted(set(PROVINCES) - discovery_provinces)
        raise ValueError(f"پوشش جستجوی استانی ناقص است: {', '.join(missing)}")
    if "ایلام" not in official_provinces:
        raise ValueError("حداقل کانال رسمی استانداری ایلام باید فعال باشد.")

    health_gate = config.get("health_gate", {})
    if not isinstance(health_gate, dict):
        raise ValueError("تنظیمات کنترل سلامت معتبر نیست.")
    ratio = float(health_gate.get("minimum_success_ratio", 0.0))
    if not 0.0 <= ratio <= 1.0:
        raise ValueError("نسبت موفقیت منابع باید بین صفر و یک باشد.")
    minimum_coverage = int(health_gate.get("minimum_province_coverage", 0))
    if not 0 <= minimum_coverage <= len(PROVINCES):
        raise ValueError("حداقل پوشش استانی معتبر نیست.")
    return config
