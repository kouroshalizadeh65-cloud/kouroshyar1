from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from .constants import EXPECTED_PUBLIC_KEY_B64, PROVINCES


def load_config(path: Path) -> dict[str, Any]:
    config = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError("فایل تنظیمات معتبر نیست.")
    if config.get("expected_public_key_b64") != EXPECTED_PUBLIC_KEY_B64:
        raise ValueError("کلید عمومی تنظیمات با نسخه نصب‌شده تطابق ندارد.")
    sources = config.get("sources")
    if not isinstance(sources, list) or not sources:
        raise ValueError("حداقل یک منبع لازم است.")
    seen_names: set[str] = set()
    for source in sources:
        if not isinstance(source, dict) or not source.get("name") or not source.get("kind"):
            raise ValueError("تعریف منبع ناقص است.")
        if source["name"] in seen_names:
            raise ValueError(f"نام منبع تکراری است: {source['name']}")
        seen_names.add(source["name"])
        province = source.get("province")
        if province is not None and province not in PROVINCES:
            raise ValueError(f"استان ناشناخته در تنظیمات: {province}")
        modes = source.get("modes", ["current"])
        if not isinstance(modes, list) or not set(modes).issubset({"current", "backfill_1405"}):
            raise ValueError(f"mode منبع معتبر نیست: {source['name']}")
    return config
