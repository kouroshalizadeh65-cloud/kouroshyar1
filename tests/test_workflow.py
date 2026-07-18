from pathlib import Path


def test_single_workflow_has_strict_validation_and_exact_commit_paths():
    root = Path(__file__).resolve().parents[1]
    workflows = list((root / ".github" / "workflows").glob("*.yml"))
    assert [p.name for p in workflows] == ["holiday-bot.yml"]
    text = workflows[0].read_text(encoding="utf-8")
    assert "python -m holiday_bot validate" in text
    assert "reports/last_run.json" not in text.split("git add", 1)[-1]
    assert "holiday_feed/holidays.json" in text
    assert "holiday_feed/working_hours.json" in text
    assert "HOLIDAY_FEED_PRIVATE_KEY_B64" in text


def test_no_sensitive_key_files_in_payload():
    root = Path(__file__).resolve().parents[1]
    forbidden = []
    for path in root.rglob("*"):
        if path.is_file() and (path.suffix.lower() in {".pem", ".key", ".jks", ".keystore"} or path.name == "key.properties"):
            forbidden.append(path)
    assert forbidden == []
