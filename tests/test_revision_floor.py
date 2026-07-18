import json
import shutil
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

import holiday_bot.engine as engine
from holiday_bot.constants import HOLIDAY_FEED_FORMAT, WORK_SCHEDULE_FEED_FORMAT
from holiday_bot.storage import load_revision_floor

ROOT = Path(__file__).resolve().parents[1]


def _payload(format_name: str, revision: int) -> dict:
    key = "holidays" if format_name == HOLIDAY_FEED_FORMAT else "schedules"
    return {"format": format_name, "revision": revision, "generatedAt": "2026-07-18T00:00:00Z", key: []}


def _prepare(repo: Path, holiday_revision: int, working_revision: int, holiday_floor: int, working_floor: int) -> None:
    shutil.copytree(ROOT, repo, ignore=shutil.ignore_patterns(".git"))
    (repo / "data/holidays.payload.json").write_text(json.dumps(_payload(HOLIDAY_FEED_FORMAT, holiday_revision)), encoding="utf-8")
    (repo / "data/working_hours.payload.json").write_text(json.dumps(_payload(WORK_SCHEDULE_FEED_FORMAT, working_revision)), encoding="utf-8")
    shutil.rmtree(repo / "holiday_feed", ignore_errors=True)
    (repo / "holiday_feed").mkdir()
    (repo / "data/revision_floor.json").write_text(json.dumps({
        "schema": "kouroshyar-feed-revision-floor-v1",
        "holidayRevisionFloor": holiday_floor,
        "workingHoursRevisionFloor": working_floor,
        "updatedAt": "2026-07-18T00:00:00Z",
        "updatedBy": "test",
    }), encoding="utf-8")


def _run(repo: Path, monkeypatch):
    key = Ed25519PrivateKey.generate()
    monkeypatch.setattr(engine, "load_private_key", lambda _path: key)
    monkeypatch.setattr(engine, "assert_expected_key", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(engine, "_fetch_source", lambda *_args, **_kwargs: [])
    return engine.run_update(repo, repo / "config/sources.yaml", repo / "unused.pem", "current", False)


def test_migration_floor_three_publishes_both_feeds_as_revision_four(tmp_path: Path, monkeypatch):
    repo = tmp_path / "repo"
    _prepare(repo, holiday_revision=1, working_revision=2, holiday_floor=3, working_floor=3)
    report = _run(repo, monkeypatch)
    assert report["holidayRevision"] == 4
    assert report["workingHoursRevision"] == 4
    assert report["revisionFloor"]["holidayRecoveryRequired"] is True
    assert report["revisionFloor"]["workingHoursRecoveryRequired"] is True
    floor = load_revision_floor(repo / "data/revision_floor.json")
    assert floor.holiday_revision_floor == 4
    assert floor.working_hours_revision_floor == 4


def test_floor_never_downgrades_and_next_recovery_advances_above_it(tmp_path: Path, monkeypatch):
    repo = tmp_path / "repo"
    _prepare(repo, holiday_revision=1, working_revision=1, holiday_floor=9, working_floor=10)
    report = _run(repo, monkeypatch)
    assert report["holidayRevision"] == 10
    assert report["workingHoursRevision"] == 11
    floor = load_revision_floor(repo / "data/revision_floor.json")
    assert floor.holiday_revision_floor == 10
    assert floor.working_hours_revision_floor == 11


def test_current_revision_above_floor_is_recorded_without_feed_downgrade(tmp_path: Path, monkeypatch):
    repo = tmp_path / "repo"
    _prepare(repo, holiday_revision=7, working_revision=8, holiday_floor=3, working_floor=3)
    report = _run(repo, monkeypatch)
    assert report["holidayRevision"] == 8
    assert report["workingHoursRevision"] == 9
    floor = load_revision_floor(repo / "data/revision_floor.json")
    assert floor.holiday_revision_floor == 8
    assert floor.working_hours_revision_floor == 9
