import json
import shutil
import subprocess
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

import holiday_bot.engine as engine
from holiday_bot.constants import HOLIDAY_FEED_FORMAT, WORK_SCHEDULE_FEED_FORMAT

ROOT = Path(__file__).resolve().parents[1]


def test_engine_recovers_higher_git_revision_and_publishes_newer_files(tmp_path: Path, monkeypatch):
    repo = tmp_path / "repo"
    shutil.copytree(ROOT, repo)
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "test"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)

    holiday_payload = {"format": HOLIDAY_FEED_FORMAT, "revision": 7, "generatedAt": "2026-07-17T00:00:00Z", "holidays": []}
    work_payload = {"format": WORK_SCHEDULE_FEED_FORMAT, "revision": 9, "generatedAt": "2026-07-17T00:00:00Z", "schedules": []}
    (repo / "data/holidays.payload.json").write_text(json.dumps(holiday_payload), encoding="utf-8")
    (repo / "data/working_hours.payload.json").write_text(json.dumps(work_payload), encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-m", "historical revisions"], cwd=repo, check=True, capture_output=True)

    (repo / "data/holidays.payload.json").write_text(json.dumps({**holiday_payload, "revision": 1}), encoding="utf-8")
    (repo / "data/working_hours.payload.json").write_text(json.dumps({**work_payload, "revision": 1}), encoding="utf-8")
    shutil.rmtree(repo / "holiday_feed", ignore_errors=True)
    (repo / "holiday_feed").mkdir()

    key = Ed25519PrivateKey.generate()
    monkeypatch.setattr(engine, "load_private_key", lambda _path: key)
    monkeypatch.setattr(engine, "assert_expected_key", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(engine, "_fetch_source", lambda *_args, **_kwargs: [])

    report = engine.run_update(repo, repo / "config/sources.yaml", repo / "unused.pem", "current", False)

    assert report["holidayRevision"] == 8
    assert report["workingHoursRevision"] == 11
    assert report["holidayRecovery"]["highestKnownRevision"] == 7
    assert report["workingHoursRecovery"]["highestKnownRevision"] == 10
    assert report["validation"]["holidays"] >= 28
    assert report["validation"]["periodicSchedules"] == 1
    assert report["validation"]["incidentSchedules"] >= 1
