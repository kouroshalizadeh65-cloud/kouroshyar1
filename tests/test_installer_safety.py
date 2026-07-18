from pathlib import Path


def test_installer_preserves_build_apk_workflow():
    package_root = Path(__file__).resolve().parents[2]
    installer = (package_root / "install_or_update_bot.ps1").read_text(encoding="utf-8")
    assert "$buildWorkflowHashBefore" in installer
    assert "Workflow ساخت APK به اشتباه حذف شده است" in installer
    assert "legacyWorkflowNamePattern" in installer
    assert '"holiday|holidays|HOLIDAY_FEED_PRIVATE_KEY_B64' not in installer
