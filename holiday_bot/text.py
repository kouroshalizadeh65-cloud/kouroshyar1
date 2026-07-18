from __future__ import annotations

import html
import re
import unicodedata

_PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def normalize_text(value: str | None) -> str:
    if not value:
        return ""
    value = html.unescape(str(value))
    value = value.translate(_PERSIAN_DIGITS)
    value = value.replace("ي", "ی").replace("ى", "ی").replace("ك", "ک")
    value = value.replace("ۀ", "ه").replace("ة", "ه")
    value = value.replace("\u200c", " ").replace("\u200f", " ").replace("\u200e", " ")
    value = "".join(ch for ch in value if unicodedata.category(ch) != "Cf")
    value = re.sub(r"[\t\r\n]+", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value


def excerpt(value: str, limit: int = 500) -> str:
    text = normalize_text(value)
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"
