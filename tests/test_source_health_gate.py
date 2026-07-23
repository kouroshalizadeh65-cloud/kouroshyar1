from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

import holiday_bot.engine as engine


ROOT = Path(__file__).resolve().parents[1]


def test_critical_source_failure_blocks_publication_but_writes_health_report(tmp_path: Path, monkeypatch):
    repo = tmp_path / "repo"
    shutil.copytree(ROOT, repo, ignore=shutil.ignore_patterns(".git", ".pytest_cache", "__pycache__"))
    before_holidays = (repo / "data/holidays.payload.json").read_bytes()
    before_hours = (repo / "data/working_hours.payload.json").read_bytes()

    key = Ed25519PrivateKey.generate()
    monkeypatch.setattr(engine, "load_private_key", lambda _path: key)
    monkeypatch.setattr(engine, "assert_expected_key", lambda *_args, **_kwargs: None)

    def fake_fetch(_client, source, _allowed, _mode):
        if source.get("critical") and source.get("kind") == "public_channel":
            raise RuntimeError("official channel unavailable")
        return []

    monkeypatch.setattr(engine, "_fetch_source", fake_fetch)

    with pytest.raises(RuntimeError, match="کنترل سلامت منابع"):
        engine.run_update(repo, repo / "config/sources.yaml", repo / "unused.pem", "current", False)

    health = json.loads((repo / "reports/source_health.json").read_text(encoding="utf-8"))
    assert health["schema"] == "kouroshyar-source-health-v2"
    assert health["healthGate"]["ok"] is False
    assert len(health["criticalFailures"]) == 1
    assert (repo / "data/holidays.payload.json").read_bytes() == before_holidays
    assert (repo / "data/working_hours.payload.json").read_bytes() == before_hours
