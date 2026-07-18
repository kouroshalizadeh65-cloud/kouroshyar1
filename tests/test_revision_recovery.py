import json
import subprocess
from pathlib import Path

from holiday_bot.constants import HOLIDAY_FEED_FORMAT
from holiday_bot.storage import load_existing_payload_state


def _write_payload(path: Path, revision: int, title: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "format": HOLIDAY_FEED_FORMAT,
        "revision": revision,
        "generatedAt": "2026-07-18T00:00:00Z",
        "holidays": [{"id": title}],
    }), encoding="utf-8")


def test_highest_revision_is_recovered_from_git_history(tmp_path: Path):
    subprocess.run(["git", "init"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "test"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmp_path, check=True)
    payload = tmp_path / "data/holidays.payload.json"
    envelope = tmp_path / "holiday_feed/holidays.json"
    _write_payload(payload, 7, "historical")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-m", "revision 7"], cwd=tmp_path, check=True, capture_output=True)
    _write_payload(payload, 1, "stale-current")

    state = load_existing_payload_state(tmp_path, envelope, payload, HOLIDAY_FEED_FORMAT)

    assert state.highest_revision == 7
    assert state.payload["holidays"] == [{"id": "historical"}]
    assert state.restore_required is True
    assert state.source.startswith("git:")


def test_current_highest_payload_does_not_require_restore_when_both_files_are_not_expected(tmp_path: Path):
    # بدون مخزن Git و بدون envelope، payload فعلی انتخاب می‌شود و نیاز به بازسازی envelope دارد.
    payload = tmp_path / "data/holidays.payload.json"
    envelope = tmp_path / "holiday_feed/holidays.json"
    _write_payload(payload, 4, "current")
    state = load_existing_payload_state(tmp_path, envelope, payload, HOLIDAY_FEED_FORMAT)
    assert state.highest_revision == 4
    assert state.current_payload_revision == 4
    assert state.restore_required is True
