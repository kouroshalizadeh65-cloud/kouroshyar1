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
    assert health["schema"] == "kouroshyar-source-health-v3"
    assert health["healthGate"]["ok"] is False
    assert health["healthGate"]["result"] == "failed_no_publish"
    assert len(health["criticalFailures"]) == 1
    assert (repo / "data/holidays.payload.json").read_bytes() == before_holidays
    assert (repo / "data/working_hours.payload.json").read_bytes() == before_hours


def test_transient_critical_rate_limit_is_reported_as_deferred_no_publish(tmp_path: Path, monkeypatch):
    from holiday_bot.extract import FetchError

    repo = tmp_path / "repo"
    shutil.copytree(ROOT, repo, ignore=shutil.ignore_patterns(".git", ".pytest_cache", "__pycache__"))
    key = Ed25519PrivateKey.generate()
    monkeypatch.setattr(engine, "load_private_key", lambda _path: key)
    monkeypatch.setattr(engine, "assert_expected_key", lambda *_args, **_kwargs: None)

    def fake_fetch(_client, source, _allowed, _mode):
        if source.get("critical") and source.get("kind") == "public_channel":
            raise FetchError(
                "HTTP 429 after retries",
                category="rate_limited",
                transient=True,
                status_code=429,
                attempts=4,
                url=source["url"],
            )
        return []

    monkeypatch.setattr(engine, "_fetch_source", fake_fetch)

    with pytest.raises(engine.HealthGateError) as caught:
        engine.run_update(repo, repo / "config/sources.yaml", repo / "unused.pem", "current", False)

    report = caught.value.report
    assert report["workflowStatus"] == "deferred_no_publish"
    assert report["publicationAllowed"] is False
    assert report["sourcesDeferred"] == 1
    health = report["sourceHealth"]
    assert health["deferred"] == 1
    assert health["hardFailed"] == 0
    assert health["criticalFailures"][0]["errorType"] == "rate_limited"
    assert health["healthGate"]["reasonDetails"][0]["transient"] is True
