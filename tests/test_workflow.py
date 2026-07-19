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
    assert "data/revision_floor.json" in text
    assert "report[\"holidayRevision\"] >= 4" in text
    assert "published-revision-floor.json" in text
    push_paths = text.split("paths:", 1)[1].split("permissions:", 1)[0]
    assert "pubspec.yaml" not in push_paths
    assert "data/manual_overrides.json" in push_paths
    assert "[bot v1.3.1]" in text


def test_no_sensitive_key_files_in_payload():
    root = Path(__file__).resolve().parents[1]
    forbidden = []
    for path in root.rglob("*"):
        if path.is_file() and (path.suffix.lower() in {".pem", ".key", ".jks", ".keystore"} or path.name == "key.properties"):
            forbidden.append(path)
    assert forbidden == []


def test_all_31_province_feeds_are_configured():
    import yaml
    from holiday_bot.constants import PROVINCES

    root = Path(__file__).resolve().parents[1]
    config = yaml.safe_load((root / "config" / "sources.yaml").read_text(encoding="utf-8"))
    configured = {item.get("province") for item in config["sources"] if item.get("province")}
    assert configured == set(PROVINCES)


def test_android_artifact_name_and_version_checks_are_derived_from_pubspec():
    root = Path(__file__).resolve().parents[1]
    text = (root / ".github" / "workflows" / "build-apk.yml").read_text(encoding="utf-8")
    assert "VERSION_SPEC=$(awk '/^version:/" in text
    assert "versionCode='$VERSION_CODE'" in text
    assert "versionName='$VERSION_NAME'" in text
    assert "name: ${{ env.ARTIFACT_NAME }}" in text
    assert "kouroshyar_v3_6_57" not in text


def test_official_ilam_portal_is_allowlisted_and_configured():
    import yaml
    root = Path(__file__).resolve().parents[1]
    config = yaml.safe_load((root / "config" / "sources.yaml").read_text(encoding="utf-8"))
    assert "portal-il.ir" in config["allowed_domains"]
    source = next(item for item in config["sources"] if item["name"] == "استانداری ایلام - اطلاعیه‌ها و بخشنامه‌ها")
    assert source["kind"] == "html_index"
    assert source["province"] == "ایلام"
    assert source["url"] == "https://www.portal-il.ir/archives/arshive1"
