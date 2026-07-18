from pathlib import Path


def test_single_holiday_workflow_has_strict_validation_publish_and_recovery():
    root = Path(__file__).resolve().parents[1]
    workflows = []
    for path in (root / ".github" / "workflows").glob("*.yml"):
        text = path.read_text(encoding="utf-8")
        if "HOLIDAY_FEED_PRIVATE_KEY_B64" in text or "KouroshYar Holiday Bot" in text:
            workflows.append(path)
    assert [p.name for p in workflows] == ["holiday-bot.yml"]
    text = workflows[0].read_text(encoding="utf-8")
    assert "fetch-depth: 0" in text
    assert "KOUROSHYAR_FORCE_PUBLISH" in text
    assert "python -m holiday_bot validate" in text
    assert "raw.githubusercontent.com" in text
    assert "git ls-remote origin refs/heads/main" in text
    assert "reports/last_run.json" not in text.split("git add", 1)[-1]
    assert "holiday_feed/holidays.json" in text
    assert "holiday_feed/working_hours.json" in text


def test_no_sensitive_key_files_in_payload():
    root = Path(__file__).resolve().parents[1]
    forbidden = []
    for path in root.rglob("*"):
        if path.is_file() and (path.suffix.lower() in {".pem", ".key", ".jks", ".keystore"} or path.name == "key.properties"):
            forbidden.append(path)
    assert forbidden == []
